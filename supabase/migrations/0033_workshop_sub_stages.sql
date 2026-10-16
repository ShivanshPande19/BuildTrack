-- 0033_workshop_sub_stages.sql
--
-- A workshop stage is one line in the project's pipeline and a fortnight of
-- work on the floor. "Workshop" covers the structural framework, the hole
-- drilling, the cladding, the paint, the branding, the electricals, the
-- insulation, the flooring, the fittings, the plumbing, the finishing — each
-- done by different people, several of them at the same time.
--
-- The project manager should not be assigning fifteen of those by name on
-- forty builds; the workshop knows its own people. So a PM hands the stage to
-- a **supervisor** (0032's flag) and says what the truck needs, and the
-- supervisor breaks it into **sub-stages** and gives each one to somebody.
--
-- Sub-stages borrow two ideas that already work rather than inventing any:
--
--   * `step`, exactly as 0031 gave it to stages — same step runs together, a
--     step opens when every earlier one is done. The supervisor sets it, so
--     *they* decide what runs alongside what on this truck, not the template.
--   * `done_by` / `done_at`, exactly as 0029 gave the checklist — who did it
--     and when, recorded by the RPC rather than written by a client.
--
-- What they deliberately do **not** borrow is the evidence machinery. The
-- stage already has a checklist that can demand photos and a photo gallery the
-- PM and client see; a second one hanging off sub-stages would be two places
-- to look for the same thing. A sub-stage answers "who is doing this, and is
-- it done" — the stage still answers "is there proof".
--
-- Idempotent: one enum, one table, one trigger, one RPC.


-- Guarded: the test harness re-applies the newest migration to prove it is
-- idempotent, and `create type` has no `if not exists`.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'task_status') then
    create type task_status as enum ('todo', 'in_progress', 'done');
  end if;
end $$;

create table if not exists public.stage_tasks (
  id          uuid primary key default gen_random_uuid(),
  stage_id    uuid not null references stages(id) on delete cascade,
  title       text not null,
  ord         int  not null default 0,
  -- Same meaning as stages.step (0031): sub-stages sharing a step run
  -- alongside each other. Null = its own step, which is `ord`.
  step        int,
  assignee_id uuid references profiles(id) on delete set null,
  status      task_status not null default 'todo',
  -- Who marked it done, and when. Written only by fn_set_task_status.
  done_by     uuid references profiles(id) on delete set null,
  done_at     timestamptz,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists idx_stage_tasks_stage    on public.stage_tasks(stage_id, ord);
create index if not exists idx_stage_tasks_assignee on public.stage_tasks(assignee_id);

comment on table public.stage_tasks is
  'The supervisor''s breakdown of a stage into work for individual people. Not the checklist: that is the PM''s condition for approving the stage.';

alter table public.stage_tasks enable row level security;


-- ════════════════════════════════════════════════════════════════════════════
-- 1. Who may touch one
--
-- Read: any staff member — the PM watches progress, the client's own screens
-- never see these. Write: the people who own the stage, plus the person the
-- sub-stage was given to, who may move only its status. The trigger below
-- draws that second line; the policy only has to get them through the door.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists stage_tasks_read  on public.stage_tasks;
drop policy if exists stage_tasks_write on public.stage_tasks;

create policy stage_tasks_read on public.stage_tasks
  for select using (public.is_staff());

create policy stage_tasks_write on public.stage_tasks
  for all
  using (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id)
    or assignee_id = auth.uid())
  with check (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id)
    or assignee_id = auth.uid());


-- ════════════════════════════════════════════════════════════════════════════
-- 2. The plan is the supervisor's; the status is whoever is doing it
--
-- Same shape as trg_guard_checklist (0029): the person doing the work may say
-- it is done and nothing else. What a sub-stage *says*, who it is for and what
-- it runs alongside are the supervisor's — otherwise a worker could hand their
-- own job to somebody else, or quietly move it out of the way of the step that
-- was waiting on it.
--
-- And, like a checklist, an approved stage's breakdown is closed: it is part
-- of what the PM signed off.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_task_rpc_begin() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('buildtrack.task_rpc', 'on', true);
end $$;

do $$
declare v_roles text := 'public';
begin
  select v_roles || coalesce(string_agg(', ' || quote_ident(rolname), ''), '')
    into v_roles
    from pg_roles where rolname in ('authenticated', 'anon');
  execute format('revoke all on function public.fn_task_rpc_begin() from %s', v_roles);
end $$;

create or replace function public.trg_guard_stage_tasks() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_assignee uuid; v_sstatus stage_status; v_stage uuid; v_row record;
begin
  if tg_op = 'DELETE' then
    v_row := old; v_stage := old.stage_id;
  else
    v_row := new; v_stage := new.stage_id;
  end if;

  -- No JWT = service role / SQL editor / seed, as everywhere else.
  if auth.uid() is null then return v_row; end if;
  if public.is_admin() then return v_row; end if;

  select p.pm_id, s.assignee_id, s.status
    into v_pm, v_assignee, v_sstatus
    from stages s join projects p on p.id = s.project_id
   where s.id = v_stage;

  -- An approved stage's breakdown is part of what was approved.
  if v_sstatus = 'done' then
    raise exception 'This stage is already approved as complete — its work items cannot be changed.'
      using errcode = '42501';
  end if;

  -- The supervisor the stage was given to, and the build's PM, own the plan.
  if v_assignee = auth.uid() or v_pm = auth.uid() then return v_row; end if;

  if tg_op = 'INSERT' then
    raise exception 'Only the supervisor this stage was assigned to can add work items.'
      using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Only the supervisor this stage was assigned to can remove work items.'
      using errcode = '42501';
  end if;

  -- Left: the person it was given to. Status is theirs; everything else is not.
  if old.assignee_id is distinct from auth.uid() then
    raise exception 'This work item is not yours.' using errcode = '42501';
  end if;
  if new.title       is distinct from old.title
     or new.step        is distinct from old.step
     or new.ord         is distinct from old.ord
     or new.assignee_id is distinct from old.assignee_id
     or new.stage_id    is distinct from old.stage_id then
    raise exception 'Only the supervisor can change what a work item says, who it is for, or what it runs alongside.'
      using errcode = '42501';
  end if;
  if (new.status is distinct from old.status
      or new.done_by is distinct from old.done_by
      or new.done_at is distinct from old.done_at)
     and coalesce(current_setting('buildtrack.task_rpc', true), '') <> 'on' then
    raise exception 'Move a work item through fn_set_task_status, so who finished it and when is recorded.'
      using errcode = '42501';
  end if;

  return v_row;
end $$;

drop trigger if exists t_guard_stage_tasks on public.stage_tasks;
create trigger t_guard_stage_tasks before insert or update or delete on public.stage_tasks
  for each row execute function public.trg_guard_stage_tasks();


-- ════════════════════════════════════════════════════════════════════════════
-- 3. Moving one
--
-- Records who finished it, refuses one whose turn has not come, and audits.
-- The step gate is 0031's rule applied inside a stage: everything in an
-- earlier sub-step has to be done first.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_set_task_status(p_task uuid, p_status task_status)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage uuid; v_title text; v_step int; v_assignee uuid;
  v_sassignee uuid; v_pm uuid; v_sstatus stage_status;
  v_open int; v_blocker text;
begin
  select t.stage_id, t.title, coalesce(t.step, t.ord), t.assignee_id,
         s.assignee_id, s.status, p.pm_id
    into v_stage, v_title, v_step, v_assignee, v_sassignee, v_sstatus, v_pm
    from stage_tasks t
    join stages   s on s.id = t.stage_id
    join projects p on p.id = s.project_id
   where t.id = p_task;
  if v_stage is null then raise exception 'Work item not found.'; end if;

  if not (public.is_admin()
          or v_assignee  = auth.uid()
          or v_sassignee = auth.uid()
          or v_pm        = auth.uid()) then
    raise exception 'Only the person this work item was given to, or their supervisor, can move it.'
      using errcode = '42501';
  end if;

  if v_sstatus = 'done' and not public.is_admin() then
    raise exception 'This stage is already approved as complete — its work items cannot be changed.';
  end if;

  -- The gate, inside the stage. An admin is let through: putting a build back
  -- in order is their job, and fn_audit records that it was them.
  if p_status <> 'todo' and not public.is_admin() then
    select count(*), min(e.title)
      into v_open, v_blocker
      from stage_tasks e
     where e.stage_id = v_stage
       and coalesce(e.step, e.ord) < v_step
       and e.status <> 'done';
    if coalesce(v_open, 0) > 0 then
      raise exception '% cannot start yet — % still has to be finished first.',
        v_title,
        case when v_open = 1 then coalesce(v_blocker, 'an earlier item')
             else v_open || ' earlier items' end;
    end if;
  end if;

  perform public.fn_task_rpc_begin();
  update stage_tasks
     set status  = p_status,
         done_by = case when p_status = 'done' then auth.uid() else null end,
         done_at = case when p_status = 'done' then now() else null end
   where id = p_task;

  perform public.fn_audit('set_task_status', 'stage_task', p_task);
end $$;

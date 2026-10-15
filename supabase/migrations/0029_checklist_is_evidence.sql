-- 0029_checklist_is_evidence.sql
--
-- A stage's checklist was a to-do list pretending to be evidence.
--
-- The whole table was:
--
--     checklist_items (id, stage_id, label, done)
--
-- and the only way `done` ever moved was a bare `update checklist_items set
-- done = …` from the client. So nothing recorded **who** ticked a check or
-- **when**, there was nowhere to attach proof that the work was actually done,
-- the write never reached `fn_audit`, and a check on a stage the PM had already
-- approved could still be un-ticked — changing the evidence after sign-off.
--
-- Meanwhile `fn_install_component` — the other thing a fitter does on a stage —
-- *is* audited. Same stage, same person, two different standards.
--
-- This migration closes that, in three parts:
--
--   (b) The record, and the freeze. Every tick goes through `fn_tick_check`,
--       which writes `done_by` / `done_at` and audits it, and refuses on a
--       stage that is already approved. A direct UPDATE of `done` is refused
--       outright, the same way `trg_guard_stages` (0026) forces every stage
--       transition through its RPC.
--
--   (c) Proof where it matters. A check can be marked `photo_required` — on
--       the template, so every build inherits it, or on one build's stage by
--       its PM. Ticking such a check needs a photo on that stage, and the row
--       keeps which photo discharged it. Not every check: "weld the frame"
--       deserves a photo, "collect the keys" does not, and demanding one for
--       all of them is how a fitter learns to photograph the floor.
--
-- It also closes two gaps in the same family, both found reading the Workshop
-- role end to end:
--
--   * `fn_install_component` allowed a part into an **approved** stage, though
--     `fn_start_stage` and `fn_submit_stage` have both refused one since 0026.
--   * …and it silently stole a part another build had reserved (0026 made
--     Store's intake an earmark: `installed_in_project_id` set while `status`
--     stays `in_stock`). The earmark was overwritten and nobody was told.
--
--   * A workshop member could insert a `delay_logs` row against **any** stage
--     on any build, because the per-role matrix grants the table by role and
--     nothing narrowed it to their own work.
--
-- Idempotent: additive columns, one new RPC, four function replacements, one
-- trigger replacement, one policy replacement.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. The columns
--
-- `done_by` / `done_at` are the record. `photo_required` is the rule. and
-- `proof_attachment_id` is which photo discharged it — ON DELETE SET NULL,
-- because deleting a photo must not delete the check, but it must stop the
-- check claiming a photo that is gone.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.checklist_items
  add column if not exists done_by             uuid references profiles(id),
  add column if not exists done_at             timestamptz,
  add column if not exists photo_required      boolean not null default false,
  add column if not exists proof_attachment_id uuid references attachments(id) on delete set null;

comment on column public.checklist_items.done_by is
  'Who ticked this check. Written only by fn_tick_check.';
comment on column public.checklist_items.photo_required is
  'This check cannot be ticked without a photo on its stage. Set on the template, or by the build''s PM.';

-- Checks already ticked before this migration have no record to recover: the
-- old write stored nothing. Leaving done_by/done_at null is the honest state —
-- "ticked, by nobody we can name" — and the app says "before this was tracked"
-- rather than inventing an actor.

alter table public.template_stage_checks
  add column if not exists photo_required boolean not null default false;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. A template's photo rule reaches the build
--
-- Body is 0012's, with `photo_required` carried through step 1b. Everything
-- else — the stage copy, the backward schedule, the BOM, the notification — is
-- unchanged, and every step stays guarded so re-onboarding cannot duplicate.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_onboard_project(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_template uuid; v_pm uuid; v_code text; v_name text; v_stages int;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can onboard a project.' using errcode = '42501';
  end if;

  select template_id, pm_id, code, name
    into v_template, v_pm, v_code, v_name
    from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  if v_template is null then
    raise exception 'Choose a workflow template before onboarding this build.';
  end if;
  if v_pm is null then
    raise exception 'Assign a project manager before onboarding this build.';
  end if;

  select count(*) into v_stages from template_stages where template_id = v_template;
  if v_stages = 0 then
    raise exception 'That workflow template has no stages — add stages to it first.';
  end if;

  insert into stages (project_id, template_stage_id, name, ord, status, discipline)
  select p_project, ts.id, ts.name, ts.ord, 'todo',
         coalesce(ts.discipline, public.fn_infer_discipline(ts.name))
    from template_stages ts
   where ts.template_id = v_template
     and not exists (select 1 from stages s where s.project_id = p_project);

  -- 1b) checklist for each stage, now carrying the template's photo rule.
  insert into checklist_items (stage_id, label, done, photo_required)
  select s.id, tsc.label, false, coalesce(tsc.photo_required, false)
    from template_stage_checks tsc
    join stages s on s.template_stage_id = tsc.template_stage_id
                 and s.project_id = p_project
   where not exists (select 1 from checklist_items ci where ci.stage_id = s.id)
   order by tsc.ord;

  perform public.fn_recompute_schedule(p_project);

  if not exists (select 1 from procurement_requirements where project_id = p_project) then
    insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, status)
    select p_project, tsi.item_catalog_id, tsi.qty, s.planned_start, 'pending'
      from template_stage_items tsi
      join stages s on s.template_stage_id = tsi.template_stage_id
                   and s.project_id = p_project;
  end if;

  perform public.fn_recompute_schedule(p_project);
  perform public.fn_recompute_progress(p_project);

  perform public.fn_notify(v_pm, 'project_assigned',
    v_code || ' is now yours',
    'A new build (' || v_name || ') has been assigned to you. Assign its stages to your team.',
    'project', p_project);
  perform public.fn_audit('onboard_project', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. Ticking a check is an action, not a field write
--
-- Same shape as the stage RPCs: the function marks the transaction sanctioned
-- and the guard stands aside for it. `true` keeps the setting
-- transaction-local, so it can never leak into the next statement on a pooled
-- connection.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_check_rpc_begin() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('buildtrack.check_rpc', 'on', true);
end $$;

revoke all on function public.fn_check_rpc_begin() from public, authenticated;

create or replace function public.fn_tick_check(
  p_item  uuid,
  p_done  boolean,
  p_proof uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage    uuid;
  v_label    text;
  v_needs    boolean;
  v_sstatus  stage_status;
  v_assignee uuid;
  v_pm       uuid;
  v_code     text;
  v_sname    text;
  v_proof    uuid;
begin
  select ci.stage_id, ci.label, ci.photo_required,
         s.status, s.assignee_id, s.name, p.pm_id, p.code
    into v_stage, v_label, v_needs, v_sstatus, v_assignee, v_sname, v_pm, v_code
    from checklist_items ci
    join stages   s on s.id = ci.stage_id
    join projects p on p.id = s.project_id
   where ci.id = p_item;
  if v_stage is null then raise exception 'Checklist item not found.'; end if;

  -- Who may tick: the person doing the work, their PM, or an admin. Same set
  -- as the p_check_write policy, named here so the RPC refuses before the
  -- policy does and the message says something useful.
  if not (public.is_admin() or v_assignee = auth.uid() or v_pm = auth.uid()) then
    raise exception 'Only the member assigned to this stage can tick its checklist.'
      using errcode = '42501';
  end if;

  -- (b) The freeze. Once the PM has approved the stage its checklist is the
  -- evidence they approved, and evidence that can still be edited is not
  -- evidence. An admin is let through deliberately: correcting a genuine
  -- mistake on a closed build is their job, and fn_audit records that it was
  -- them.
  if v_sstatus = 'done' and not public.is_admin() then
    raise exception 'This stage is already approved as complete — its checklist is part of the approval and cannot be changed.';
  end if;

  if p_done then
    -- (c) Proof where the check asks for it.
    if coalesce(v_needs, false) then
      if p_proof is null then
        raise exception 'Check "%" needs a photo before it can be ticked — take one on this stage first.', v_label;
      end if;
      -- The photo has to be on *this* stage. Without this the id of any
      -- attachment in the system would satisfy the rule.
      if not exists (select 1 from attachments a
                      where a.id = p_proof
                        and a.owner_type = 'stage'
                        and a.owner_id = v_stage) then
        raise exception 'That photo is not on this stage.';
      end if;
    end if;
    v_proof := p_proof;
  else
    -- Un-ticking drops the record with it: a check that is not done was not
    -- done by anybody, and leaving a stale name on it reads as if it were.
    v_proof := null;
  end if;

  perform public.fn_check_rpc_begin();
  update checklist_items
     set done                = p_done,
         done_by             = case when p_done then auth.uid() else null end,
         done_at             = case when p_done then now() else null end,
         proof_attachment_id = v_proof
   where id = p_item;

  perform public.fn_audit(
    case when p_done then 'tick_check' else 'untick_check' end,
    'checklist_item', p_item);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. The guard
--
-- 0028 handed the *wording* of a checklist to the PM. This adds the three
-- things that make the tick itself trustworthy:
--
--   * `done` and its record move only inside fn_tick_check. A client that
--     writes the column directly is refused, so the audit trail has no hole.
--   * `photo_required` is the PM's to set, like the label.
--   * an approved stage's checklist is closed to everyone but an admin —
--     including to adding and removing items, which 0028 left open to the PM.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_guard_checklist() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_stage uuid; v_sstatus stage_status; v_row record; v_sanctioned boolean;
begin
  -- NEW does not exist on DELETE and OLD does not exist on INSERT, so the row
  -- to return (and the stage to look up) is chosen before anything touches
  -- either. `coalesce(new, old)` looks tidy and is not valid on records.
  if tg_op = 'DELETE' then
    v_row := old; v_stage := old.stage_id;
  else
    v_row := new; v_stage := new.stage_id;
  end if;

  -- No JWT = service role / SQL editor / seed / onboarding, as everywhere else.
  if auth.uid() is null then return v_row; end if;
  if public.is_admin() then return v_row; end if;

  v_sanctioned := coalesce(current_setting('buildtrack.check_rpc', true), '') = 'on';

  select p.pm_id, s.status into v_pm, v_sstatus
    from stages s join projects p on p.id = s.project_id
   where s.id = v_stage;

  -- An approved stage's checklist is the evidence the PM signed off on. Not
  -- even they may rewrite it now; an admin can, and fn_audit records it.
  -- fn_tick_check refuses this case too, with a sentence about the approval —
  -- this is the backstop for a direct write.
  if v_sstatus = 'done' then
    raise exception 'This stage is already approved as complete — its checklist cannot be changed.'
      using errcode = '42501';
  end if;

  -- Ticking: only ever through fn_tick_check, so done_by / done_at / the proof
  -- are always written together and always audited.
  if tg_op = 'UPDATE' and not v_sanctioned
     and (new.done                is distinct from old.done
       or new.done_by             is distinct from old.done_by
       or new.done_at             is distinct from old.done_at
       or new.proof_attachment_id is distinct from old.proof_attachment_id) then
    raise exception 'Tick a checklist item through fn_tick_check, so who ticked it and when is recorded.'
      using errcode = '42501';
  end if;

  if v_pm = auth.uid() then return v_row; end if;

  if tg_op = 'INSERT' then
    raise exception 'Only the project manager can add items to a stage checklist.'
      using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Only the project manager can remove items from a stage checklist.'
      using errcode = '42501';
  elsif new.label          is distinct from old.label
     or new.stage_id       is distinct from old.stage_id
     or new.photo_required is distinct from old.photo_required then
    raise exception 'Only the project manager can change what a checklist item says, or whether it needs a photo.'
      using errcode = '42501';
  end if;

  return v_row;
end $$;

drop trigger if exists t_guard_checklist on public.checklist_items;
create trigger t_guard_checklist before insert or update or delete on public.checklist_items
  for each row execute function public.trg_guard_checklist();


-- ════════════════════════════════════════════════════════════════════════════
-- 5. A part cannot be fitted into an approved stage, or taken off another build
--
-- Body is 0009's, with two guards added after the stock check. The caller
-- check, the status check and the audit are unchanged.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_install_component(p_component uuid, p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_project  uuid; v_assignee uuid; v_cstatus component_status;
  v_serial   text; v_code text; v_sstatus stage_status;
  v_reserved uuid; v_rcode text;
begin
  select s.project_id, s.assignee_id, s.status, p.code
    into v_project, v_assignee, v_sstatus, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid() or public.has_role(array['store'])) then
    raise exception 'Only the member assigned to this stage can install parts into it.' using errcode = '42501';
  end if;

  -- An approved stage is closed. fn_start_stage and fn_submit_stage have both
  -- refused one since 0026; this did not, so a part could be added to the
  -- record of a stage the PM had already signed off — and the truck record and
  -- the client's build timeline both changed after the approval.
  if v_sstatus = 'done' then
    raise exception 'That stage is already approved as complete — a part cannot be added to it now.';
  end if;

  select status, serial_number, installed_in_project_id
    into v_cstatus, v_serial, v_reserved
    from component_instances where id = p_component;
  if v_cstatus is null then raise exception 'That component is not in the system — ask Store to log it first.'; end if;
  if v_cstatus <> 'in_stock' then
    raise exception 'Serial % is marked % — only in-stock parts can be installed.', coalesce(v_serial, '?'), v_cstatus;
  end if;

  -- An in-stock part that already names a build is Store's earmark for that
  -- build (0026: intake reserves, it does not install). Fitting it elsewhere
  -- used to overwrite the earmark silently, so the build it was bought for
  -- lost its part and nobody was told.
  if v_reserved is not null and v_reserved <> v_project then
    select code into v_rcode from projects where id = v_reserved;
    raise exception 'Serial % is reserved for % — ask Store to release it before fitting it to %.',
      coalesce(v_serial, '?'), coalesce(v_rcode, 'another build'), v_code;
  end if;

  update component_instances
     set status = 'installed',
         installed_in_project_id = v_project,
         installed_stage_id      = p_stage,
         installed_by            = auth.uid(),
         install_date            = current_date
   where id = p_component;

  perform public.fn_audit('install_component', 'component_instance', p_component);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. A delay is reported against your own work
--
-- The per-role matrix grants `delay_logs` to {admin,pm,workshop} — and giving
-- the fitter a way to say "the steel did not arrive" is right, because they are
-- the one who knows. But the grant is by role, so any workshop member could
-- log a delay against any stage on any build, including one they have never
-- seen. Narrowed to their own stage; admin and the build's PM keep the full
-- table, since attributing a slip across the build is the PM's job.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists delay_logs_write on public.delay_logs;
create policy delay_logs_write on public.delay_logs for all
  using (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id))
  with check (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id));

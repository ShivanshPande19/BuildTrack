-- 0031_stages_run_in_steps.sql
--
-- A build is a sequence, and the app has always half-known it.
--
--   * `fn_decide_stage` already starts the next stage on approval:
--         where status = 'todo' and ord > v_ord order by ord limit 1
--   * `fn_recompute_schedule` already lays the plan out backwards:
--         order by s.ord desc
--
-- So `ord` has been the running order since 0009 — but nothing enforced it.
-- `fn_start_stage` asked only "are you the assignee, and is it not done yet",
-- so a fitter could start Fabrication while the design was still with the
-- client, and Electrical while the chassis did not exist. Both happened. The
-- schedule, the progress bar and the client's timeline all then describe work
-- that could not have been done in the order they claim.
--
-- Enforcing `ord` strictly would be too blunt, though: on a real truck the
-- countertop and the electricals both wait for the chassis, and then run
-- *alongside each other*. A rule that made the electrician wait for the
-- carpenter would be obeyed by marking the carpentry done early, which is
-- worse than no rule.
--
-- So stages run in **steps**. Every stage belongs to a step; stages sharing a
-- step run in parallel; a step opens only when every stage in every earlier
-- step is approved. `ord` keeps its old job — the order things are listed in —
-- and `step` is the new one: what waits for what.
--
-- Backfilled `step = ord`, so every build that exists today behaves exactly as
-- it did, one stage at a time, until someone groups two stages deliberately.
--
-- This migration also lets a **project manager** onboard their own build, so an
-- admin can hand over a project with no plan at all and the PM builds it.
--
-- Idempotent: two additive columns, five function replacements, one view.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. The step
-- ════════════════════════════════════════════════════════════════════════════

alter table public.stages          add column if not exists step int;
alter table public.template_stages add column if not exists step int;

-- Existing rows keep today's behaviour exactly: one stage per step, in `ord`.
update public.stages          set step = ord where step is null;
update public.template_stages set step = ord where step is null;

alter table public.stages          alter column step set default 1;
alter table public.template_stages alter column step set default 1;

comment on column public.stages.step is
  'Stages sharing a step run in parallel. A step opens when every earlier step is done. `ord` is only the display order.';

create index if not exists idx_stages_project_step on public.stages(project_id, step);


-- ════════════════════════════════════════════════════════════════════════════
-- 2. `step` is the plan, so it is the PM's
--
-- Body is 0026's, with `step` added to the list of columns only the PM and an
-- admin may move. It belongs there for the same reason `ord` does: it is the
-- shape of the build, not the state of one stage — and it is also the way a PM
-- fixes a plan that came out of the template wrong, by grouping two stages on
-- *this* build without touching the template or every other build using it.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_guard_stages() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid;
begin
  -- No JWT = service role / SQL editor / cron / seed.
  if auth.uid() is null then return new; end if;

  -- Inside one of the sanctioned stage RPCs.
  if coalesce(current_setting('buildtrack.stage_rpc', true), '') = 'on' then
    return new;
  end if;

  select pm_id into v_pm from projects where id = new.project_id;
  if public.is_admin() or v_pm = auth.uid() then return new; end if;

  if new.assignee_id   is distinct from old.assignee_id
     or new.discipline is distinct from old.discipline
     or new.ord        is distinct from old.ord
     or new.step       is distinct from old.step
     or new.project_id is distinct from old.project_id
     or new.bay_id     is distinct from old.bay_id
     or new.planned_start is distinct from old.planned_start
     or new.planned_end   is distinct from old.planned_end
     or new.assigned_due   is distinct from old.assigned_due
     or new.assigned_start is distinct from old.assigned_start then
    raise exception 'Only the project manager can change a stage''s assignment or schedule.'
      using errcode = '42501';
  end if;

  -- A stage moves forward through Start / Submit / Approve, never by hand.
  if new.status       is distinct from old.status
     or new.actual_start is distinct from old.actual_start
     or new.actual_end   is distinct from old.actual_end then
    raise exception 'Use Start work and Submit for approval to move this stage — it cannot be set directly.'
      using errcode = '42501';
  end if;

  return new;
end $$;

drop trigger if exists t_guard_stages on public.stages;
create trigger t_guard_stages before update on public.stages
  for each row execute function public.trg_guard_stages();


-- ════════════════════════════════════════════════════════════════════════════
-- 3. What is holding a stage up
--
-- One definition, so the screens and the RPC can never disagree about whether
-- a stage is open. `security_invoker` keeps each caller's own RLS.
-- ════════════════════════════════════════════════════════════════════════════

drop view if exists public.v_stage_gate;
create view public.v_stage_gate with (security_invoker = on) as
  select
    s.id         as stage_id,
    s.project_id,
    coalesce(s.step, s.ord) as step,
    exists (
      select 1 from stages e
       where e.project_id = s.project_id
         and coalesce(e.step, e.ord) < coalesce(s.step, s.ord)
         and e.status <> 'done') as is_locked,
    (select e.name from stages e
      where e.project_id = s.project_id
        and coalesce(e.step, e.ord) < coalesce(s.step, s.ord)
        and e.status <> 'done'
      order by coalesce(e.step, e.ord), e.ord
      limit 1) as blocked_by,
    (select count(*) from stages e
      where e.project_id = s.project_id
        and coalesce(e.step, e.ord) < coalesce(s.step, s.ord)
        and e.status <> 'done') as blocked_by_count
  from stages s;

grant select on public.v_stage_gate to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. A stage cannot start before its turn
--
-- Body is 0026's, with the gate added after the status checks. An admin is let
-- through: putting a build back in order after something went wrong is their
-- job, and fn_audit records that it was them.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_start_stage(p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_assignee uuid; v_project uuid; v_pm uuid; v_status stage_status;
  v_stage text; v_code text; v_step int; v_blocker text; v_open int;
begin
  select s.assignee_id, s.project_id, s.status, s.name, coalesce(s.step, s.ord), p.pm_id, p.code
    into v_assignee, v_project, v_status, v_stage, v_step, v_pm, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid() or v_pm = auth.uid()) then
    raise exception 'Only the member assigned to this stage can start it.' using errcode = '42501';
  end if;
  if v_status = 'done' then
    raise exception 'This stage is already approved as complete.';
  end if;
  if v_status = 'in_progress' then return; end if;

  -- The gate. Everything in an earlier step has to be approved first.
  if not public.is_admin() then
    select count(*), min(e.name)
      into v_open, v_blocker
      from stages e
     where e.project_id = v_project
       and coalesce(e.step, e.ord) < v_step
       and e.status <> 'done';
    if coalesce(v_open, 0) > 0 then
      raise exception '% cannot start yet — % still has to be approved first.',
        v_stage,
        case when v_open = 1 then coalesce(v_blocker, 'an earlier stage')
             else v_open || ' earlier stages' end;
    end if;
  end if;

  perform public.fn_stage_rpc_begin();
  update stages
     set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
   where id = p_stage;

  perform public.fn_notify(v_pm, 'stage_started',
    v_code || ' · ' || v_stage || ' started',
    'Work has begun on this stage.', 'stage', p_stage);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. Approving the last stage of a step opens the whole next one
--
-- Body is 0009's, with the auto-start rewritten. It used to pull exactly one
-- stage (`ord > v_ord … limit 1`), which with steps would start one of a pair
-- and leave the other sitting in `todo` with nothing to open it.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_decide_stage(
  p_approval uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage uuid; v_project uuid; v_pm uuid; v_sub uuid; v_astatus approval_status;
  v_stage_name text; v_code text; v_pname text; v_step int;
  v_next_step int; r record;
begin
  select a.stage_id, a.submitted_by, a.status, s.project_id, s.name,
         coalesce(s.step, s.ord), p.pm_id, p.code, p.name
    into v_stage, v_sub, v_astatus, v_project, v_stage_name, v_step, v_pm, v_code, v_pname
    from stage_approvals a
    join stages   s on s.id = a.stage_id
    join projects p on p.id = s.project_id
   where a.id = p_approval
     for no key update of a;
  if v_stage is null then raise exception 'Approval not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only this build''s project manager can decide this submission.' using errcode = '42501';
  end if;
  if v_astatus <> 'pending' then
    raise exception 'This submission has already been decided.';
  end if;

  update stage_approvals
     set status = case when p_approve then 'approved'::approval_status
                                      else 'rejected'::approval_status end,
         note = nullif(btrim(coalesce(p_note, '')), ''),
         decided_at = now()
   where id = p_approval;

  perform public.fn_stage_rpc_begin();

  if p_approve then
    update stages set status = 'done', actual_end = coalesce(actual_end, current_date)
     where id = v_stage;

    -- Only once *everything* in this step is approved does the next one open.
    -- A step with one stage behaves exactly as before.
    if not exists (
      select 1 from stages
       where project_id = v_project
         and coalesce(step, ord) = v_step
         and status <> 'done')
    then
      select min(coalesce(step, ord)) into v_next_step
        from stages
       where project_id = v_project
         and coalesce(step, ord) > v_step
         and status = 'todo';

      if v_next_step is not null then
        for r in
          select id, name, assignee_id from stages
           where project_id = v_project
             and coalesce(step, ord) = v_next_step
             and status = 'todo'
           order by ord
        loop
          update stages
             set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
           where id = r.id;
          perform public.fn_notify(r.assignee_id, 'stage_assigned',
            v_code || ' · ' || r.name || ' is up next',
            'The step before this one is approved — this stage is now in progress.',
            'stage', r.id);
        end loop;
      end if;
    end if;

    perform public.fn_notify(v_sub, 'approved',
      v_code || ' · ' || v_stage_name || ' approved',
      'Your work was approved. Nice one.', 'stage', v_stage);

    perform public.fn_notify_client(v_project, 'stage_done',
      v_pname || ': ' || v_stage_name || ' complete',
      'Another stage of your build is finished. Open the app to see the latest.');
  else
    update stages set status = 'rework' where id = v_stage;
    perform public.fn_notify(v_sub, 'rework',
      v_code || ' · ' || v_stage_name || ' sent back',
      coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Your project manager asked for changes on this stage.'),
      'stage', v_stage);
  end if;

  perform public.fn_recompute_progress(v_project);
  perform public.fn_audit(case when p_approve then 'approve_stage' else 'reject_stage' end, 'stage', v_stage);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. The plan is laid out a step at a time
--
-- Body is 0026's. The backward walk moved the cursor once per *stage*, so two
-- stages running in parallel would each be given their own slot and the build
-- would look longer than it is. A step takes as long as its longest stage.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_recompute_schedule(
  p_project uuid,
  p_rebaseline_assigned boolean default false
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_target date;
  v_cursor date;
  r record;
  v_dur int;
begin
  select target_delivery_date into v_target from projects where id = p_project;
  if v_target is null then return; end if;

  v_cursor := v_target;
  -- Walk steps from last to first. Every stage in a step shares the window, and
  -- the step is as long as its longest stage.
  for r in
    select coalesce(s.step, s.ord) as step,
           greatest(max(coalesce(ts.default_duration_days, 1)), 1) as dur
      from stages s
      left join template_stages ts on ts.id = s.template_stage_id
     where s.project_id = p_project
     group by coalesce(s.step, s.ord)
     order by 1 desc
  loop
    v_dur := r.dur;
    update stages
       set planned_end   = v_cursor,
           planned_start = v_cursor - (v_dur - 1)
     where project_id = p_project
       and coalesce(step, ord) = r.step;
    v_cursor := (v_cursor - v_dur);
  end loop;

  -- Full re-plan (delivery date changed): snap the PM's committed dates to the
  -- new plan so a stage is never "Due" after delivery. Completed stages keep
  -- their historical dates.
  if p_rebaseline_assigned then
    update stages
       set assigned_start = planned_start,
           assigned_due   = planned_end
     where project_id = p_project
       and status <> 'done';

    -- …and move each still-pending material's needed-by onto the new plan, so
    -- the order-by engine alerts against the schedule that is actually live.
    -- Anchored on the stage the requirement's item belongs to in the template
    -- BOM; a requirement with no such anchor keeps the PM's own needed-by.
    update procurement_requirements pr
       set needed_by_date = anchor.planned_start
      from (
        select tsi.item_catalog_id, min(s.planned_start) as planned_start
          from template_stage_items tsi
          join stages s on s.template_stage_id = tsi.template_stage_id
                       and s.project_id = p_project
         where s.planned_start is not null
         group by tsi.item_catalog_id
      ) anchor
     where pr.project_id      = p_project
       and pr.status          = 'pending'
       and pr.item_catalog_id = anchor.item_catalog_id
       and pr.needed_by_date is distinct from anchor.planned_start;
  end if;

  -- order-by date for each requirement = needed_by - lead - buffer
  update procurement_requirements pr
     set order_by_date = pr.needed_by_date - ic.lead_time_days - ic.buffer_days
    from item_catalog ic
   where pr.item_catalog_id = ic.id
     and pr.project_id = p_project
     and pr.needed_by_date is not null;

  -- The plan moved, so on-track / at-risk / delayed may have moved with it.
  perform public.fn_recompute_status(p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7. A project manager can set up their own build
--
-- An admin creating a build has had to choose its workflow template there and
-- then. That is the wrong moment for it: the admin knows the client, the code
-- and who is managing it; the PM is the one who knows what this truck actually
-- involves. So an admin can now hand over a build with no plan at all, and its
-- PM builds the plan themselves.
--
-- Body is 0029's, with the caller check widened and `step` carried through
-- from the template. Everything else — the guards, the BOM, the backward
-- schedule, the notification — is unchanged, and every step stays idempotent so
-- running it twice cannot duplicate a thing.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_onboard_project(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_template uuid; v_pm uuid; v_code text; v_name text; v_stages int;
begin
  select template_id, pm_id, code, name
    into v_template, v_pm, v_code, v_name
    from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  -- The build's own PM may set it up, as well as an admin.
  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only an admin or this build''s project manager can set up its plan.'
      using errcode = '42501';
  end if;

  if v_template is null then
    raise exception 'Choose a workflow template before setting up this build.';
  end if;
  if v_pm is null then
    raise exception 'Assign a project manager before setting up this build.';
  end if;

  select count(*) into v_stages from template_stages where template_id = v_template;
  if v_stages = 0 then
    raise exception 'That workflow template has no stages — add stages to it first.';
  end if;

  insert into stages (project_id, template_stage_id, name, ord, step, status, discipline)
  select p_project, ts.id, ts.name, ts.ord, coalesce(ts.step, ts.ord), 'todo',
         coalesce(ts.discipline, public.fn_infer_discipline(ts.name))
    from template_stages ts
   where ts.template_id = v_template
     and not exists (select 1 from stages s where s.project_id = p_project);

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

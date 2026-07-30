-- ============================================================================
-- 0009_workflow.sql — Assignment chain + permission hardening
--
-- Makes the real operating chain work end-to-end and enforces it in the DB:
--
--   Admin  ─ creates project (+ the client's login) ─► assigns a PM
--   PM     ─ sees only their builds ─► assigns each stage to the right discipline
--   Staff  ─ sees only their assigned work ─► starts it, uploads, submits
--   PM     ─ approves ─► stage done ─► next stage starts ─► client sees progress
--
-- Everything that used to be "trusted to the UI" is now enforced server-side:
-- who may assign, who may approve, which role may do which stage, and who may
-- write which table. See docs/WORKFLOW_AUDIT.md for the issue list this closes.
-- Safe to re-run (idempotent).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1. SCHEMA — a stage now knows its discipline and its assignment metadata
-- ════════════════════════════════════════════════════════════════════════════

-- Which role is supposed to do a stage. Lets the PM's assign sheet recommend
-- the right people and lets the DB reject "design work → welder" mistakes.
alter table template_stages add column if not exists discipline user_role;

alter table stages add column if not exists discipline     user_role;
alter table stages add column if not exists assigned_by    uuid references profiles(id) on delete set null;
alter table stages add column if not exists assigned_at    timestamptz;
alter table stages add column if not exists assigned_start date;
alter table stages add column if not exists assigned_due   date;

-- Who assigned the PM to this build, and when (accountability).
alter table projects add column if not exists pm_assigned_by uuid references profiles(id) on delete set null;
alter table projects add column if not exists pm_assigned_at timestamptz;

-- The rejection reason had nowhere to live, and a submission had no timestamp.
alter table stage_approvals add column if not exists note       text;
alter table stage_approvals add column if not exists created_at timestamptz not null default now();

create index if not exists idx_stages_assignee   on stages(assignee_id);
create index if not exists idx_stages_discipline on stages(discipline);
create index if not exists idx_projects_pm       on projects(pm_id);
create index if not exists idx_stage_appr_stage  on stage_approvals(stage_id, status);

-- Collapse any duplicate pending submissions that the old code could create,
-- keeping the newest, then make duplicates impossible (E5).
delete from stage_approvals a
 where a.status = 'pending'
   and exists (select 1 from stage_approvals b
                where b.stage_id = a.stage_id and b.status = 'pending'
                  and (b.created_at, b.id) > (a.created_at, a.id));

create unique index if not exists uq_stage_approval_pending
  on stage_approvals(stage_id) where status = 'pending';

-- Best-effort discipline from a stage name, so existing templates/projects work
-- immediately without anyone re-typing their workflows. A PM can always override.
create or replace function public.fn_infer_discipline(p_name text)
returns user_role language sql immutable as $$
  select case
    when p_name ~* '(design|layout|render|branding|graphic|3d|drawing)'   then 'design'::user_role
    when p_name ~* '(store|inventory|stock|intake|goods|material receipt)' then 'store'::user_role
    when p_name ~* '(deliver|handover|commission|test|qc|quality|service)' then 'service'::user_role
    else 'workshop'::user_role
  end
$$;

update template_stages set discipline = public.fn_infer_discipline(name) where discipline is null;
update stages           set discipline = public.fn_infer_discipline(name) where discipline is null;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Removing a person must not be blocked by their history (F5)
--    Every FK that points at a person becomes ON DELETE SET NULL, so offboarding
--    a PM / assignee / uploader can never fail with a foreign-key violation.
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare r record; v_notnull boolean;
begin
  for r in
    select con.conname,
           con.conrelid::regclass::text as tbl,
           att.attname                  as col
      from pg_constraint con
      join pg_class     rel on rel.oid = con.conrelid
      join pg_namespace ns  on ns.oid  = rel.relnamespace
      join unnest(con.conkey) as k(attnum) on true
      join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
     where con.contype   = 'f'
       and ns.nspname    = 'public'
       and con.confrelid = 'public.profiles'::regclass
       and con.confdeltype = 'a'                    -- still NO ACTION
       and array_length(con.conkey, 1) = 1
  loop
    select attnotnull into v_notnull
      from pg_attribute where attrelid = r.tbl::regclass and attname = r.col;
    if v_notnull then continue; end if;             -- e.g. notifications.user_id (cascades already)

    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I foreign key (%I) '
                   'references public.profiles(id) on delete set null',
                   r.tbl, r.conname, r.col);
  end loop;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. HELPERS — role / ownership tests used by both the RPCs and the policies
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.has_role(p_roles text[]) returns boolean
  language sql stable as
$$ select coalesce(public.my_role()::text = any(p_roles), false) $$;

create or replace function public.is_pm_of(p_project uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from projects where id = p_project and pm_id = auth.uid()) $$;

create or replace function public.is_pm_of_stage(p_stage uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (
     select 1 from stages s join projects p on p.id = s.project_id
      where s.id = p_stage and p.pm_id = auth.uid()) $$;

create or replace function public.is_stage_assignee(p_stage uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from stages where id = p_stage and assignee_id = auth.uid()) $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. NOTIFICATIONS + AUDIT (B4 / B5)
--    notifications RLS is "own rows only", so nobody could ever notify anyone
--    else. These definer helpers are the single sanctioned way to do it.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_notify(
  p_user uuid, p_type text, p_title text,
  p_body text default null, p_entity_type text default null, p_entity_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;              -- unassigned / no login yet
  insert into notifications (user_id, type, title, body, entity_type, entity_id)
  values (p_user, p_type, p_title, p_body, p_entity_type, p_entity_id);
end $$;

-- Notify a project's client (resolves the client_account's login).
create or replace function public.fn_notify_client(
  p_project uuid, p_type text, p_title text, p_body text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_user uuid;
begin
  select ca.contact_user_id into v_user
    from projects p join client_accounts ca on ca.id = p.client_account_id
   where p.id = p_project;
  perform public.fn_notify(v_user, p_type, p_title, p_body, 'project', p_project);
end $$;

create or replace function public.fn_audit(p_action text, p_entity_type text, p_entity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (actor_id, action, entity_type, entity_id)
  values (auth.uid(), p_action, p_entity_type, p_entity_id);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. PROGRESS / STATUS ENGINE (F1 / F2)
--    projects.status and projects.current_stage_id were written by nothing, so
--    every build looked "on_track" forever and every dashboard lied.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_recompute_current_stage(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  -- what's actually being worked on
  select id into v_id from stages
   where project_id = p_project and status in ('in_progress', 'rework')
   order by ord limit 1;
  -- else the next thing up
  if v_id is null then
    select id into v_id from stages
     where project_id = p_project and status = 'todo' order by ord limit 1;
  end if;
  -- else everything is done → the final stage
  if v_id is null then
    select id into v_id from stages where project_id = p_project order by ord desc limit 1;
  end if;

  update projects set current_stage_id = v_id
   where id = p_project and current_stage_id is distinct from v_id;
end $$;

-- delivered → delayed → at_risk → on_track
create or replace function public.fn_recompute_status(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_delivered date; v_late int; v_risk int; v_status project_status;
begin
  select actual_delivery_date into v_delivered from projects where id = p_project;

  if v_delivered is not null then
    v_status := 'delivered';
  else
    -- a stage that isn't done has already blown past its planned end
    select count(*) into v_late from stages
     where project_id = p_project and status <> 'done'
       and planned_end is not null and planned_end < current_date;

    if v_late > 0 then
      v_status := 'delayed';
    else
      -- a stage that should have started hasn't
      select count(*) into v_risk from stages
       where project_id = p_project and status = 'todo'
         and planned_start is not null and planned_start <= current_date;

      -- or a part is past its order-by date and still unordered (Hero #1)
      if v_risk = 0 then
        select count(*) into v_risk from procurement_requirements
         where project_id = p_project and status = 'pending'
           and order_by_date is not null and order_by_date <= current_date;
      end if;

      v_status := case when v_risk > 0 then 'at_risk'::project_status
                                       else 'on_track'::project_status end;
    end if;
  end if;

  update projects set status = v_status
   where id = p_project and status is distinct from v_status;
end $$;

-- progress % + status + current stage, all in one place
create or replace function public.fn_recompute_progress(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_total int; v_done int; v_pct int;
begin
  select count(*), count(*) filter (where status = 'done')
    into v_total, v_done from stages where project_id = p_project;
  v_pct := case when v_total > 0 then round(100.0 * v_done / v_total) else 0 end;

  update projects set progress_pct = v_pct
   where id = p_project and progress_pct is distinct from v_pct;

  perform public.fn_recompute_current_stage(p_project);
  perform public.fn_recompute_status(p_project);
end $$;

-- For a daily cron: statuses drift with the calendar, not only with edits.
create or replace function public.fn_refresh_all_statuses()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from projects loop
    perform public.fn_recompute_status(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. STEP 2 — Admin assigns / changes the Project Manager (B1, B2, B6)
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_assign_pm(p_project uuid, p_pm uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_old uuid; v_code text; v_name text; v_role user_role; v_pstatus user_status;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can assign a project manager.' using errcode = '42501';
  end if;
  if p_pm is null then
    raise exception 'A build must always have a project manager.';
  end if;

  select pm_id, code, name into v_old, v_code, v_name from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  select role, status into v_role, v_pstatus from profiles where id = p_pm;
  if v_role is null then
    raise exception 'That member does not exist.';
  end if;
  if v_role <> 'pm' then
    raise exception 'Projects can only be assigned to a Project Manager (that member is %).', v_role;
  end if;
  if v_pstatus = 'disabled' then
    raise exception 'That project manager''s account is disabled.';
  end if;

  if v_old is not distinct from p_pm then return; end if;   -- nothing to do

  update projects
     set pm_id = p_pm, pm_assigned_by = auth.uid(), pm_assigned_at = now()
   where id = p_project;

  perform public.fn_notify(p_pm, 'project_assigned',
    v_code || ' is now yours',
    'You have been assigned as project manager for ' || v_name || '. Assign its stages to get the build moving.',
    'project', p_project);

  if v_old is not null then
    perform public.fn_notify(v_old, 'project_reassigned',
      v_code || ' was reassigned',
      v_name || ' now has a different project manager.', 'project', p_project);
  end if;

  perform public.fn_audit('assign_pm', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7. STEP 1 — Onboarding (A5, B1)
--    Refuses to create a half-built project: no template, no stages in the
--    template, or no PM would each leave a build nobody can ever work on.
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

  -- 1) stages from the template, each carrying its discipline (idempotent)
  insert into stages (project_id, template_stage_id, name, ord, status, discipline)
  select p_project, ts.id, ts.name, ts.ord, 'todo',
         coalesce(ts.discipline, public.fn_infer_discipline(ts.name))
    from template_stages ts
   where ts.template_id = v_template
     and not exists (select 1 from stages s where s.project_id = p_project);

  -- 2) backward-schedule them (fills planned_start / planned_end)
  perform public.fn_recompute_schedule(p_project);

  -- 3) auto-generate procurement requirements from the template BOM (Hero #1)
  if not exists (select 1 from procurement_requirements where project_id = p_project) then
    insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, status)
    select p_project, tsi.item_catalog_id, tsi.qty, s.planned_start, 'pending'
      from template_stage_items tsi
      join stages s on s.template_stage_id = tsi.template_stage_id
                   and s.project_id = p_project;
  end if;

  -- 4) order-by dates + progress/status/current stage
  perform public.fn_recompute_schedule(p_project);
  perform public.fn_recompute_progress(p_project);

  perform public.fn_notify(v_pm, 'project_assigned',
    v_code || ' is now yours',
    'A new build (' || v_name || ') has been assigned to you. Assign its stages to your team.',
    'project', p_project);
  perform public.fn_audit('onboard_project', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 8. STEP 4 — PM assigns a stage to the right discipline (D1-D5)
--    p_override = the PM deliberately moving this stage to another discipline.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_assign_stage(
  p_stage uuid, p_assignee uuid,
  p_start date default null, p_due date default null,
  p_override boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_project uuid; v_pm uuid; v_disc user_role; v_old uuid;
  v_stage text; v_code text; v_pname text;
  v_role user_role; v_pstatus user_status;
begin
  select s.project_id, s.discipline, s.assignee_id, s.name, p.pm_id, p.code, p.name
    into v_project, v_disc, v_old, v_stage, v_pm, v_code, v_pname
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only this build''s project manager can assign its stages.' using errcode = '42501';
  end if;
  if p_start is not null and p_due is not null and p_due < p_start then
    raise exception 'The due date cannot be before the start date.';
  end if;

  if p_assignee is not null then
    select role, status into v_role, v_pstatus from profiles where id = p_assignee;
    if v_role is null then
      raise exception 'That member does not exist.';
    end if;
    if v_role not in ('workshop', 'design', 'store', 'service') then
      raise exception 'Build stages can only go to workshop, design, store or service members (that member is %).', v_role;
    end if;
    if v_pstatus = 'disabled' then
      raise exception 'That member''s account is disabled.';
    end if;
    if v_disc is not null and v_role <> v_disc and not p_override then
      raise exception 'This is a % stage but that member works in % — confirm the override to assign anyway.',
        v_disc, v_role;
    end if;
    -- PM explicitly moved the stage to another discipline: record it
    if v_disc is null or v_role <> v_disc then
      update stages set discipline = v_role where id = p_stage;
    end if;
  end if;

  update stages
     set assignee_id    = p_assignee,
         assigned_by    = case when p_assignee is null then null else auth.uid() end,
         assigned_at    = case when p_assignee is null then null else now()      end,
         assigned_start = case when p_assignee is null then null else p_start    end,
         assigned_due   = case when p_assignee is null then null else p_due      end
   where id = p_stage;

  if p_assignee is not null and p_assignee is distinct from v_old then
    perform public.fn_notify(p_assignee, 'stage_assigned',
      v_code || ' · ' || v_stage,
      'You have been assigned this stage on ' || v_pname ||
      coalesce(' · due ' || to_char(p_due, 'DD Mon'), '') || '.',
      'stage', p_stage);
  end if;
  if v_old is not null and v_old is distinct from p_assignee then
    perform public.fn_notify(v_old, 'stage_unassigned',
      v_code || ' · ' || v_stage || ' moved on',
      'This stage is no longer assigned to you.', 'stage', p_stage);
  end if;

  perform public.fn_audit(
    case when p_assignee is null then 'unassign_stage' else 'assign_stage' end, 'stage', p_stage);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 9. STEP 5 — The assignee's own actions (E2, E3, E4, E5, E9)
-- ════════════════════════════════════════════════════════════════════════════

-- "Start work" — the missing transition that left every stage stuck on todo.
create or replace function public.fn_start_stage(p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_assignee uuid; v_project uuid; v_pm uuid; v_status stage_status; v_stage text; v_code text;
begin
  select s.assignee_id, s.project_id, s.status, s.name, p.pm_id, p.code
    into v_assignee, v_project, v_status, v_stage, v_pm, v_code
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

  update stages
     set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
   where id = p_stage;

  perform public.fn_notify(v_pm, 'stage_started',
    v_code || ' · ' || v_stage || ' started',
    'Work has begun on this stage.', 'stage', p_stage);
end $$;

-- Workshop scan-to-install: link an in-stock part to a truck + stage.
create or replace function public.fn_install_component(p_component uuid, p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_project uuid; v_assignee uuid; v_cstatus component_status; v_serial text; v_code text;
begin
  select s.project_id, s.assignee_id, p.code
    into v_project, v_assignee, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid() or public.has_role(array['store'])) then
    raise exception 'Only the member assigned to this stage can install parts into it.' using errcode = '42501';
  end if;

  select status, serial_number into v_cstatus, v_serial
    from component_instances where id = p_component;
  if v_cstatus is null then raise exception 'That component is not in the system — ask Store to log it first.'; end if;
  if v_cstatus <> 'in_stock' then
    raise exception 'Serial % is marked % — only in-stock parts can be installed.', coalesce(v_serial, '?'), v_cstatus;
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

-- Submit a finished stage for the PM's approval.
create or replace function public.fn_submit_stage(p_stage uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_assignee uuid; v_project uuid; v_pm uuid; v_status stage_status;
        v_stage text; v_code text; v_id uuid; v_me text;
begin
  select s.assignee_id, s.project_id, s.status, s.name, p.pm_id, p.code
    into v_assignee, v_project, v_status, v_stage, v_pm, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid()) then
    raise exception 'Only the member assigned to this stage can submit it.' using errcode = '42501';
  end if;
  if v_status = 'done' then
    raise exception 'This stage is already approved as complete.';
  end if;
  -- Without a PM the submission would sit in a black hole forever (E4).
  if v_pm is null then
    raise exception 'This build has no project manager yet — ask an admin to assign one before submitting.';
  end if;
  if exists (select 1 from stage_approvals where stage_id = p_stage and status = 'pending') then
    raise exception 'This stage is already waiting for approval.';
  end if;

  insert into stage_approvals (stage_id, submitted_by, approver_id, status)
  values (p_stage, auth.uid(), v_pm, 'pending')
  returning id into v_id;

  if v_status = 'todo' then
    update stages set status = 'in_progress',
                      actual_start = coalesce(actual_start, current_date)
     where id = p_stage;
  end if;

  select coalesce(full_name, email) into v_me from profiles where id = auth.uid();
  perform public.fn_notify(v_pm, 'stage_submitted',
    v_code || ' · ' || v_stage || ' needs approval',
    coalesce(v_me, 'A team member') || ' marked this stage complete.', 'stage', p_stage);

  return v_id;
end $$;

-- PM decides: approve (stage done, next stage starts) or send back for rework.
create or replace function public.fn_decide_stage(
  p_approval uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage uuid; v_project uuid; v_pm uuid; v_sub uuid; v_astatus approval_status;
  v_stage_name text; v_code text; v_pname text; v_ord int;
  v_next uuid; v_next_name text; v_next_assignee uuid;
begin
  select a.stage_id, a.submitted_by, a.status, s.project_id, s.name, s.ord, p.pm_id, p.code, p.name
    into v_stage, v_sub, v_astatus, v_project, v_stage_name, v_ord, v_pm, v_code, v_pname
    from stage_approvals a
    join stages   s on s.id = a.stage_id
    join projects p on p.id = s.project_id
   where a.id = p_approval;
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

  if p_approve then
    update stages set status = 'done', actual_end = coalesce(actual_end, current_date)
     where id = v_stage;

    -- pull the next queued stage into progress so the build never stalls silently
    select id, name, assignee_id into v_next, v_next_name, v_next_assignee
      from stages
     where project_id = v_project and status = 'todo' and ord > v_ord
     order by ord limit 1;

    if v_next is not null then
      update stages set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
       where id = v_next;
      perform public.fn_notify(v_next_assignee, 'stage_assigned',
        v_code || ' · ' || v_next_name || ' is up next',
        'The previous stage was approved — this one is now in progress.', 'stage', v_next);
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
-- 10. Client design decision (E8)
--     The client only has SELECT on design_artifacts, so the app's direct
--     UPDATE silently changed nothing while showing "Design approved".
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_client_decide_design(
  p_artifact uuid, p_approve boolean, p_feedback text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_project uuid; v_ca uuid; v_creator uuid; v_ver uuid;
  v_type design_type; v_dstatus design_status; v_code text; v_pm uuid; v_fb text;
begin
  select a.project_id, a.created_by, a.current_version_id, a.type, a.status,
         p.client_account_id, p.code, p.pm_id
    into v_project, v_creator, v_ver, v_type, v_dstatus, v_ca, v_code, v_pm
    from design_artifacts a join projects p on p.id = a.project_id
   where a.id = p_artifact;
  if v_project is null then raise exception 'Design not found.'; end if;

  if v_ca is null or v_ca is distinct from public.my_client_account() then
    raise exception 'You can only review designs for your own build.' using errcode = '42501';
  end if;
  if v_dstatus <> 'pending_approval' then
    raise exception 'This design is not waiting for your approval.';
  end if;

  v_fb := nullif(btrim(coalesce(p_feedback, '')), '');
  if not p_approve and v_fb is null then
    raise exception 'Please tell the design team what you would like changed.';
  end if;

  update design_artifacts
     set status = case when p_approve then 'approved'::design_status
                                      else 'revision'::design_status end,
         client_feedback = case when p_approve then null else v_fb end
   where id = p_artifact;

  -- a real, auditable decision record (the table existed but was never used)
  if v_ver is not null then
    insert into design_approvals (version_id, client_user_id, status, feedback, decided_at)
    values (v_ver, auth.uid(),
            case when p_approve then 'approved'::approval_status
                                else 'changes_requested'::approval_status end, v_fb, now());
  end if;

  perform public.fn_notify(v_creator,
    case when p_approve then 'approved' else 'revision' end,
    v_code || ' · ' || v_type || ' design ' || case when p_approve then 'approved' else 'needs changes' end,
    coalesce(v_fb, 'The client approved this design.'), 'design', p_artifact);

  perform public.fn_notify(v_pm,
    case when p_approve then 'approved' else 'revision' end,
    v_code || ' · client ' || case when p_approve then 'approved the ' else 'requested changes on the ' end
      || v_type || ' design',
    v_fb, 'design', p_artifact);

  perform public.fn_audit(
    case when p_approve then 'approve_design' else 'request_design_changes' end, 'design_artifact', p_artifact);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 11. Recall notification (E10) — the "Notify all" button was a no-op
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_recall_notify(p_item uuid, p_note text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int := 0; v_item text; r record;
begin
  if not public.has_role(array['admin', 'store', 'service']) then
    raise exception 'Only store, service or admin can raise a recall notice.' using errcode = '42501';
  end if;

  select name into v_item from item_catalog where id = p_item;

  for r in
    select distinct p.id as pid, p.code, p.name, p.pm_id
      from component_instances ci
      join projects p on p.id = ci.installed_in_project_id
     where ci.item_catalog_id = p_item
       and ci.installed_in_project_id is not null
  loop
    perform public.fn_notify(r.pm_id, 'recall',
      'Recall check · ' || coalesce(v_item, 'component'),
      coalesce(p_note, 'This part is installed on ' || r.code || '. Please arrange an inspection.'),
      'project', r.pid);

    perform public.fn_notify_client(r.pid, 'recall',
      'Service notice for ' || r.name,
      coalesce(p_note, 'We need to inspect a part on your truck. Our service team will contact you.'));

    v_count := v_count + 1;
  end loop;

  perform public.fn_audit('recall_notify', 'item_catalog', p_item);
  return v_count;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 12. GUARD TRIGGERS — the real enforcement, since the definer RPCs above run
--     as the table owner and therefore bypass RLS. Triggers always fire.
-- ════════════════════════════════════════════════════════════════════════════

-- Only an admin owns "who runs this build" and its identity (C1).
create or replace function public.trg_guard_projects() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- No JWT = service role / SQL editor / cron / seed. RLS already blocks anon,
  -- so anything reaching here without a user is trusted server-side work.
  if auth.uid() is null then return new; end if;
  if public.is_admin() then return new; end if;

  -- Clearing pm_id is what an ON DELETE SET NULL cascade does when a PM is
  -- offboarded; RLS already stops a PM from doing it by hand (its WITH CHECK
  -- demands pm_id = auth.uid()). Only *taking* a build is blocked here.
  if new.pm_id is distinct from old.pm_id and new.pm_id is not null then
    raise exception 'Only an admin can change a build''s project manager.' using errcode = '42501';
  end if;
  if new.code              is distinct from old.code
     or new.client_account_id is distinct from old.client_account_id
     or new.template_id       is distinct from old.template_id then
    raise exception 'Only an admin can change a build''s code, client or workflow template.'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_guard_projects on projects;
create trigger t_guard_projects before update on projects
  for each row execute function public.trg_guard_projects();

-- An assignee may move their own work forward, never re-plan it (D4).
create or replace function public.trg_guard_stages() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid;
begin
  -- No JWT = service role / SQL editor / cron / seed (see trg_guard_projects).
  if auth.uid() is null then return new; end if;

  select pm_id into v_pm from projects where id = new.project_id;
  if public.is_admin() or v_pm = auth.uid() then return new; end if;

  if new.assignee_id   is distinct from old.assignee_id
     or new.discipline is distinct from old.discipline
     or new.ord        is distinct from old.ord
     or new.project_id is distinct from old.project_id
     or new.bay_id     is distinct from old.bay_id
     or new.planned_start is distinct from old.planned_start
     or new.planned_end   is distinct from old.planned_end
     or new.assigned_due   is distinct from old.assigned_due
     or new.assigned_start is distinct from old.assigned_start then
    raise exception 'Only the project manager can change a stage''s assignment or schedule.'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_guard_stages on stages;
create trigger t_guard_stages before update on stages
  for each row execute function public.trg_guard_stages();


-- ════════════════════════════════════════════════════════════════════════════
-- 13. RLS — from "any staff can write anything" to the documented matrix
--     (DataModel.md §10). Reads stay staff-wide (roles need context); writes
--     are now per-role. Closes C1, D4, E13, F4, F6, F8.
-- ════════════════════════════════════════════════════════════════════════════

-- ── PROFILES: a client no longer reads the whole staff directory (F4) ──
drop policy if exists p_profiles_read on profiles;
drop policy if exists p_profiles_read_staff on profiles;
drop policy if exists p_profiles_read_self  on profiles;
create policy p_profiles_read_staff on profiles for select using (public.is_staff());
create policy p_profiles_read_self  on profiles for select using (id = auth.uid());

-- ── PROJECTS: only an admin creates or deletes a build (C1) ──
drop policy if exists p_projects_write  on projects;
drop policy if exists p_projects_insert on projects;
drop policy if exists p_projects_update on projects;
drop policy if exists p_projects_delete on projects;
create policy p_projects_insert on projects for insert with check (public.is_admin());
create policy p_projects_delete on projects for delete using (public.is_admin());
create policy p_projects_update on projects for update
  using      (public.is_admin() or pm_id = auth.uid())
  with check (public.is_admin() or pm_id = auth.uid());

-- ── STAGES: PM plans, assignee executes (D4) ──
drop policy if exists p_stages_staff  on stages;
drop policy if exists p_stages_read   on stages;
drop policy if exists p_stages_insert on stages;
drop policy if exists p_stages_update on stages;
drop policy if exists p_stages_delete on stages;
create policy p_stages_read   on stages for select using (public.is_staff());
create policy p_stages_insert on stages for insert
  with check (public.is_admin() or public.is_pm_of(project_id));
create policy p_stages_delete on stages for delete
  using (public.is_admin() or public.is_pm_of(project_id));
create policy p_stages_update on stages for update
  using      (public.is_admin() or public.is_pm_of(project_id) or assignee_id = auth.uid())
  with check (public.is_admin() or public.is_pm_of(project_id) or assignee_id = auth.uid());

-- ── CHECKLIST: PM writes the list, the assignee ticks it (E13) ──
drop policy if exists p_check_staff  on checklist_items;
drop policy if exists p_check_read   on checklist_items;
drop policy if exists p_check_client on checklist_items;
drop policy if exists p_check_write  on checklist_items;
create policy p_check_read on checklist_items for select using (public.is_staff());
create policy p_check_client on checklist_items for select using (
  exists (select 1 from stages s join projects p on p.id = s.project_id
           where s.id = checklist_items.stage_id
             and p.client_account_id = public.my_client_account()));
create policy p_check_write on checklist_items for all
  using      (public.is_admin() or public.is_pm_of_stage(stage_id) or public.is_stage_assignee(stage_id))
  with check (public.is_admin() or public.is_pm_of_stage(stage_id) or public.is_stage_assignee(stage_id));

-- ── Per-role write access on the operational tables (F6) ──
-- read = every staff member · write = only the role that owns that data
do $$
declare
  spec text[][] := array[
    ['vendors',                  '{admin,procurement}'],
    ['item_catalog',             '{admin,procurement,pm}'],
    ['purchase_orders',          '{admin,procurement}'],
    ['po_lines',                 '{admin,procurement}'],
    ['goods_receipts',           '{admin,procurement,store}'],
    ['stock_items',              '{admin,store}'],
    ['component_instances',      '{admin,store}'],
    ['procurement_requirements', '{admin,pm}'],
    ['workflow_templates',       '{admin,pm}'],
    ['template_stages',          '{admin,pm}'],
    ['template_stage_items',     '{admin,pm}'],
    ['bays',                     '{admin,pm}'],
    ['delay_logs',               '{admin,pm,workshop}'],
    ['stage_approvals',          '{admin,pm}'],
    ['service_visits',           '{admin,service}']
  ];
  i int;
  t text;
  roles text;
begin
  for i in 1 .. array_length(spec, 1) loop
    t     := spec[i][1];
    roles := spec[i][2];

    execute format('drop policy if exists %I on public.%I', t || '_staff', t);
    execute format('drop policy if exists %I on public.%I', t || '_read',  t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);

    execute format(
      'create policy %I on public.%I for select using (public.is_staff())', t || '_read', t);
    execute format(
      'create policy %I on public.%I for all using (public.has_role(%L)) with check (public.has_role(%L))',
      t || '_write', t, roles, roles);
  end loop;
end $$;

-- Procurement doesn't own requirements (the PM plans them) but must be able to
-- flip one to "ordered"/"received" when it raises a PO.
drop policy if exists procurement_requirements_procure on procurement_requirements;
create policy procurement_requirements_procure on procurement_requirements for update
  using (public.has_role(array['procurement'])) with check (public.has_role(array['procurement']));

-- The BOM table came from 0005 with its own policy name.
drop policy if exists tsi_staff on template_stage_items;

-- ── AUDIT LOG: admin-readable, written only by the functions above (F8) ──
drop policy if exists audit_log_staff on audit_log;
drop policy if exists audit_log_read  on audit_log;
drop policy if exists audit_log_write on audit_log;
create policy audit_log_read on audit_log for select using (public.is_admin());

-- ── CLIENT ACCOUNTS: staff read, admin writes (was: any staff could edit) ──
drop policy if exists p_ca_staff       on client_accounts;
drop policy if exists p_ca_read_staff  on client_accounts;
drop policy if exists p_ca_admin       on client_accounts;
create policy p_ca_read_staff on client_accounts for select using (public.is_staff());
create policy p_ca_admin      on client_accounts for all
  using (public.is_admin()) with check (public.is_admin());

-- ── DESIGN: designers own it, the client decides via fn_client_decide_design ──
drop policy if exists p_design_staff on design_artifacts;
drop policy if exists p_design_read  on design_artifacts;
drop policy if exists p_design_write on design_artifacts;
create policy p_design_read  on design_artifacts for select using (public.is_staff());
create policy p_design_write on design_artifacts for all
  using      (public.has_role(array['admin','design']))
  with check (public.has_role(array['admin','design']));

drop policy if exists p_dver_staff on design_versions;
drop policy if exists p_dver_read  on design_versions;
drop policy if exists p_dver_write on design_versions;
create policy p_dver_read  on design_versions for select using (public.is_staff());
create policy p_dver_write on design_versions for all
  using      (public.has_role(array['admin','design']))
  with check (public.has_role(array['admin','design']));

drop policy if exists p_dappr_staff on design_approvals;
drop policy if exists p_dappr_read  on design_approvals;
drop policy if exists p_dappr_write on design_approvals;
create policy p_dappr_read  on design_approvals for select using (public.is_staff());
create policy p_dappr_write on design_approvals for all
  using      (public.has_role(array['admin','design']))
  with check (public.has_role(array['admin','design']));

-- ── TICKETS: service resolves them; the client's own policies stay ──
drop policy if exists p_tickets_staff on tickets;
drop policy if exists p_tickets_read  on tickets;
drop policy if exists p_tickets_write on tickets;
create policy p_tickets_read  on tickets for select using (public.is_staff());
create policy p_tickets_write on tickets for all
  using      (public.has_role(array['admin','service']))
  with check (public.has_role(array['admin','service']));


-- ════════════════════════════════════════════════════════════════════════════
-- 14. v_order_due leaked every build's procurement data to any signed-in user,
--     clients included, because a view runs with its owner's rights (F3).
-- ════════════════════════════════════════════════════════════════════════════

alter view public.v_order_due set (security_invoker = on);


-- ════════════════════════════════════════════════════════════════════════════
-- 15. Bring existing rows up to date (statuses, progress, current stage)
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare r record;
begin
  for r in select id from projects loop
    perform public.fn_recompute_progress(r.id);
  end loop;
end $$;

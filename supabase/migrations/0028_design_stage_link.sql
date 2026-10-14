-- 0028_design_stage_link.sql
--
-- The Design role ran as two systems that never spoke to each other.
--
--   Stage flow:   assign → start → tick checklist → submit → PM approves → done
--   Design flow:  create → upload .glb → submit → the CLIENT approves
--
-- `design_artifacts` carried no reference to a stage, and nothing on either
-- side consulted the other. So all of this was possible, and none of it was
-- caught anywhere:
--
--   * a designer ticking "Layout approved by client" with the client never
--     having opened it;
--   * the client approving a design and **nothing happening to the stage** —
--     `fn_client_decide_design` only wrote the artifact's status and sent
--     notifications;
--   * a PM approving a design stage as done while the design sat in draft;
--   * a build reaching 100% and being delivered with no approved design at all
--     — neither `fn_recompute_progress` nor `fn_mark_delivered` mentions
--     designs.
--
-- The client-approval loop worked perfectly and had no bearing on whether the
-- build was actually finished. This connects them.
--
-- 1. `design_artifacts.stage_id` — which stage a design is the deliverable for.
-- 2. A design-discipline stage cannot be submitted until a design is approved.
-- 3. Client approval tells the stage's assignee and the PM that it can move.
-- 4. A stage's checklist is the PM's to write; the assignee may only tick it.
-- 5. Stage names like "Client sign-off" are recognised as design work.
--
-- Idempotent.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. A design belongs to a stage
--
-- Nullable, and ON DELETE SET NULL: designs made before this migration have no
-- stage, and a design must survive its stage being re-planned. The link is an
-- answer to "which stage does this design discharge", not an ownership claim.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.design_artifacts
  add column if not exists stage_id uuid references stages(id) on delete set null;

create index if not exists idx_design_stage on public.design_artifacts (stage_id);

-- Backfill what can be known without guessing: a build with exactly one design
-- stage and designs that have no stage yet. Where a build has two design stages
-- there is no safe answer, so those stay null and fall back to the
-- project-wide rule in §2.
update public.design_artifacts a
   set stage_id = s.id
  from stages s
 where a.stage_id is null
   and s.project_id = a.project_id
   and s.discipline = 'design'
   and (select count(*) from stages s2
         where s2.project_id = a.project_id and s2.discipline = 'design') = 1;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. A design stage is not done until a design is approved
--
-- The deliverable of "Design & Layout" is an approved design. Submitting it
-- without one is a claim nobody can back, and it was the single easiest way to
-- make a build's progress bar lie.
--
-- The rule is deliberately forgiving about *which* design: if this stage has
-- designs linked to it, one of them must be approved; otherwise any approved
-- design on the build will do. That lets a build whose designs predate this
-- migration keep working, and it does not punish a team that keeps its layout
-- approved while a branding revision is still with the client.
--
-- Everything else about fn_submit_stage is unchanged from 0026.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_submit_stage(p_stage uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_assignee uuid; v_project uuid; v_pm uuid; v_status stage_status;
        v_stage text; v_code text; v_id uuid; v_me text; v_disc user_role;
        v_linked int; v_ok int;
begin
  select s.assignee_id, s.project_id, s.status, s.name, s.discipline, p.pm_id, p.code
    into v_assignee, v_project, v_status, v_stage, v_disc, v_pm, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid()) then
    raise exception 'Only the member assigned to this stage can submit it.' using errcode = '42501';
  end if;
  if v_status = 'done' then
    raise exception 'This stage is already approved as complete.';
  end if;
  if v_pm is null then
    raise exception 'This build has no project manager yet — ask an admin to assign one before submitting.';
  end if;
  if exists (select 1 from stage_approvals where stage_id = p_stage and status = 'pending') then
    raise exception 'This stage is already waiting for approval.';
  end if;

  -- A design stage needs an approved design behind it.
  if v_disc = 'design' then
    select count(*) into v_linked from design_artifacts where stage_id = p_stage;
    if v_linked > 0 then
      select count(*) into v_ok
        from design_artifacts
       where stage_id = p_stage and status = 'approved';
      if v_ok = 0 then
        raise exception 'The client has not approved a design for this stage yet. Submit the design for approval first, or wait for their decision.';
      end if;
    else
      select count(*) into v_ok
        from design_artifacts
       where project_id = v_project and status = 'approved';
      if v_ok = 0 then
        raise exception 'No design on this build has been approved by the client yet. A design stage is only finished once the client has signed off on a design.';
      end if;
    end if;
  end if;

  insert into stage_approvals (stage_id, submitted_by, approver_id, status)
  values (p_stage, auth.uid(), v_pm, 'pending')
  returning id into v_id;

  if v_status = 'todo' then
    perform public.fn_stage_rpc_begin();
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


-- fn_create_design gains the stage it discharges. The app passes the design
-- stage the designer is assigned on that build, so a design created from
-- "My design stages" is linked without anybody choosing anything.
create or replace function public.fn_create_design(
  p_project     uuid,
  p_type        design_type,
  p_model_url   text    default null,
  p_image_url   text    default null,
  p_change_note text    default null,
  p_submit      boolean default false,
  p_stage       uuid    default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_artifact uuid; v_version uuid; v_code text; v_pname text; v_pm uuid; v_sproj uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can create a design.' using errcode = '42501';
  end if;

  select code, name, pm_id into v_code, v_pname, v_pm from projects where id = p_project;
  if v_code is null then raise exception 'Build not found.'; end if;

  -- A stage from another build would quietly break the submit rule for both.
  if p_stage is not null then
    select project_id into v_sproj from stages where id = p_stage;
    if v_sproj is null then raise exception 'Stage not found.'; end if;
    if v_sproj <> p_project then
      raise exception 'That stage belongs to a different build.';
    end if;
  end if;

  insert into design_artifacts (project_id, stage_id, type, status, created_by)
  values (p_project, p_stage, p_type,
          (case when p_submit then 'pending_approval' else 'draft' end)::design_status,
          auth.uid())
  returning id into v_artifact;

  insert into design_versions (artifact_id, version_no, model_url, file_url, change_note)
  values (v_artifact, 1, nullif(p_model_url, ''), nullif(p_image_url, ''), nullif(p_change_note, ''))
  returning id into v_version;

  update design_artifacts set current_version_id = v_version where id = v_artifact;

  if p_submit then
    perform public.fn_notify_client(p_project, 'design_submitted',
      'A new design is ready for your approval',
      'The design team has shared the ' || p_type || ' design for ' || v_pname ||
      '. Open the app to approve it or ask for changes.');
    perform public.fn_notify(v_pm, 'design_submitted',
      v_code || ' · ' || p_type || ' design sent to the client',
      'The design team submitted it for client approval.', 'design', v_artifact);
  end if;

  perform public.fn_audit('create_design', 'design_artifact', v_artifact);
  return v_artifact;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. The client's decision reaches the stage
--
-- Approving a design is the event that unblocks a design stage, and the person
-- holding that stage was the last to hear about it — they were told the design
-- was approved, not that their stage could now move. A rejection matters just
-- as much: the stage is going nowhere until a new version goes round.
--
-- Body is 0009's, with the stage-side notification added at the end.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_client_decide_design(
  p_artifact uuid, p_approve boolean, p_feedback text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_project uuid; v_ca uuid; v_creator uuid; v_ver uuid; v_stage uuid;
  v_type design_type; v_dstatus design_status; v_code text; v_pm uuid; v_fb text;
  r record;
begin
  select a.project_id, a.created_by, a.current_version_id, a.type, a.status, a.stage_id,
         p.client_account_id, p.code, p.pm_id
    into v_project, v_creator, v_ver, v_type, v_dstatus, v_stage, v_ca, v_code, v_pm
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

  -- Tell whoever holds the design stage what this means for *their* work.
  -- The stage the design is linked to, or every open design stage on the build
  -- when the design predates the link.
  for r in
    select s.id, s.name, s.assignee_id
      from stages s
     where s.project_id = v_project
       and s.status <> 'done'
       and (s.id = v_stage or (v_stage is null and s.discipline = 'design'))
  loop
    perform public.fn_notify(r.assignee_id,
      case when p_approve then 'approved' else 'revision' end,
      v_code || ' · ' || r.name ||
        case when p_approve then ' can be submitted' else ' is still waiting' end,
      case when p_approve
        then 'The client approved the ' || v_type || ' design, so this stage can go to your project manager now.'
        else 'The client asked for changes on the ' || v_type || ' design, so this stage stays open until a new version is approved.'
      end,
      'stage', r.id);
  end loop;

  perform public.fn_audit(
    case when p_approve then 'approve_design' else 'request_design_changes' end, 'design_artifact', p_artifact);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. A checklist is the plan, not the worker's notes
--
-- `p_check_write` (0009) grants the stage's assignee full write on its checklist
-- so they can tick items off. It also lets them rename an item, delete one, or
-- add their own — which quietly turns the PM's definition of done into whatever
-- the person doing the work would rather it said.
--
-- The assignee keeps `done`. The label and the list itself belong to the PM and
-- the admin, who now also have a screen to edit them with.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_guard_checklist() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_stage uuid; v_row record;
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

  select p.pm_id into v_pm
    from stages s join projects p on p.id = s.project_id
   where s.id = v_stage;
  if v_pm = auth.uid() then return v_row; end if;

  if tg_op = 'INSERT' then
    raise exception 'Only the project manager can add items to a stage checklist.'
      using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Only the project manager can remove items from a stage checklist.'
      using errcode = '42501';
  elsif new.label is distinct from old.label or new.stage_id is distinct from old.stage_id then
    raise exception 'Only the project manager can change what a checklist item says.'
      using errcode = '42501';
  end if;

  return v_row;
end $$;

drop trigger if exists t_guard_checklist on public.checklist_items;
create trigger t_guard_checklist before insert or update or delete on public.checklist_items
  for each row execute function public.trg_guard_checklist();


-- ════════════════════════════════════════════════════════════════════════════
-- 5. Design work is recognised by more than the word "design"
--
-- The discipline of a stage is inferred from its name when a template does not
-- state one. "Client sign-off", "Mockup review" and "Concept" are design work
-- by any reading, and all three fell through to workshop — so the PM's assign
-- sheet recommended fabricators for them and the override had to be confirmed
-- every time.
--
-- Only the inference changes. A template that states its discipline, and every
-- stage already on a build, are untouched.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_infer_discipline(p_name text)
returns user_role language sql immutable as $$
  select case
    when p_name ~* '(design|layout|render|branding|graphic|3d|drawing|mockup|concept|artwork|sign.?off|client.?approval)'
      then 'design'::user_role
    when p_name ~* '(store|inventory|stock|intake|goods|material receipt)'
      then 'store'::user_role
    when p_name ~* '(deliver|handover|commission|test|qc|quality|service)'
      then 'service'::user_role
    else 'workshop'::user_role
  end
$$;

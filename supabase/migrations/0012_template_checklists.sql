-- 0012_template_checklists.sql — stages arrive with a real checklist
--
-- checklist_items was never populated by anything: no screen and no function
-- created a single row, so every stage's checklist was empty. The PM approval
-- screen now shows the checklist, which makes that emptiness visible — so this
-- gives a template a per-stage checklist and copies it onto each stage when a
-- build is onboarded, the same way the BOM (template_stage_items) already
-- becomes procurement requirements.

-- ========== per-stage checklist on a template ==========
create table if not exists template_stage_checks (
  id                uuid primary key default gen_random_uuid(),
  template_stage_id uuid not null references template_stages(id) on delete cascade,
  label             text not null,
  ord               int  not null default 0
);
create index if not exists idx_tsc_stage on template_stage_checks(template_stage_id);

alter table template_stage_checks enable row level security;

-- Read = any staff (screens need the context); write = admin/pm, who own the
-- templates — mirrors the per-role matrix set for template_stage_items in 0009.
drop policy if exists tsc_read  on template_stage_checks;
drop policy if exists tsc_write on template_stage_checks;
create policy tsc_read  on template_stage_checks for select using (public.is_staff());
create policy tsc_write on template_stage_checks for all
  using      (public.has_role(array['admin','pm']))
  with check (public.has_role(array['admin','pm']));

-- ========== onboarding now also seeds each stage's checklist ==========
-- Full replacement of the 0009 function with one extra, idempotent step (1b):
-- copy the template's checklist labels onto the freshly created stages.
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

  -- 1b) checklist for each stage, from the template's checklist (idempotent).
  --     Guarded per stage so re-onboarding never duplicates the list.
  insert into checklist_items (stage_id, label, done)
  select s.id, tsc.label, false
    from template_stage_checks tsc
    join stages s on s.template_stage_id = tsc.template_stage_id
                 and s.project_id = p_project
   where not exists (select 1 from checklist_items ci where ci.stage_id = s.id)
   order by tsc.ord;

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

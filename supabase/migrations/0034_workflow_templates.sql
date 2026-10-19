-- 0034_workflow_templates.sql
--
-- A workflow template is the plan a build starts from, and it is the one part
-- of the app that could only ever be *added to*: written once, from a form
-- that pre-filled seven stages nobody asked for, as a chain of separate client
-- inserts. A network blip halfway left a template with three of its seven
-- stages and no way to tell.
--
-- Three things change.
--
-- **A template is saved in one transaction.** fn_save_template takes the whole
-- plan — stages, their parallel steps, checklist, parts and work items — as one
-- JSON payload and writes it or writes nothing. Admins and PMs, the same two
-- roles the template tables have always granted.
--
-- **A template can carry the workshop breakdown.** 0033 let a supervisor split a
-- stage into work items on one build. Retyping the same fifteen on every truck
-- is what a template is for, so a template stage can now hold them too, and
-- onboarding copies them onto the build — unassigned, because who does them is
-- the supervisor's call on the day, not the template's.
--
-- **Templates are created, never rewritten in place.** `stages.template_stage_id`
-- references template_stages with no ON DELETE, so every running build points
-- at the template stages it was made from — and the BOM lookup on the stage
-- screen depends on that link. Replacing a template's stages would either fail
-- on that foreign key or, if it were loosened, silently cut every running build
-- off from its materials. So a change to a plan is a new template (the app
-- offers "start from this one"), and running builds keep exactly what they were
-- onboarded with.
--
-- Idempotent: one table, two columns, two functions replaced or added.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. Who made a template, and when
-- ════════════════════════════════════════════════════════════════════════════

alter table public.workflow_templates
  add column if not exists created_by uuid references profiles(id) on delete set null,
  add column if not exists created_at timestamptz not null default now();


-- ════════════════════════════════════════════════════════════════════════════
-- 2. The workshop breakdown, on the template
--
-- Same shape as stage_tasks minus who-is-doing-it: a template knows the jobs a
-- stage is made of and which of them run together, never who will do them.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.template_stage_tasks (
  id                uuid primary key default gen_random_uuid(),
  template_stage_id uuid not null references template_stages(id) on delete cascade,
  title             text not null,
  ord               int  not null default 0,
  -- Same meaning as stage_tasks.step (0033). Null = its own step, which is ord.
  step              int
);
create index if not exists idx_tst_stage on public.template_stage_tasks(template_stage_id, ord);

alter table public.template_stage_tasks enable row level security;

drop policy if exists tst_read  on public.template_stage_tasks;
drop policy if exists tst_write on public.template_stage_tasks;
create policy tst_read  on public.template_stage_tasks for select using (public.is_staff());
create policy tst_write on public.template_stage_tasks for all
  using      (public.has_role(array['admin','pm']))
  with check (public.has_role(array['admin','pm']));


-- ════════════════════════════════════════════════════════════════════════════
-- 3. Saving a template, all or nothing
--
-- p_stages is an ordered JSON array; each element:
--
--   { "name": "Workshop", "days": 14, "step": 2, "discipline": "workshop",
--     "items":  [ { "item_catalog_id": "<uuid>", "qty": 2 } ],
--     "checks": [ { "label": "Frame squared", "photo_required": true } ],
--     "tasks":  [ { "title": "Structural framework", "step": 1 } ] }
--
-- `step` falls back to the stage's position and `discipline` to the name-based
-- inference at onboarding, so a minimal payload of names alone still works.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_save_template(
  p_name       text,
  p_truck_type text  default null,
  p_stages     jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_tpl   uuid;
  v_ts    uuid;
  v_stage jsonb;
  v_ord   int := 0;
  v_name  text;
  v_disc  user_role;
  v_el    jsonb;
  v_i     int;
begin
  if not public.has_role(array['admin','pm']) then
    raise exception 'Only an admin or a project manager can create a workflow.'
      using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_name, '')), '') is null then
    raise exception 'A workflow needs a name.';
  end if;
  if jsonb_typeof(coalesce(p_stages, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_stages, '[]'::jsonb)) = 0 then
    raise exception 'A workflow needs at least one stage.';
  end if;

  insert into workflow_templates (name, truck_type, created_by)
  values (btrim(p_name), nullif(btrim(coalesce(p_truck_type, '')), ''), auth.uid())
  returning id into v_tpl;

  for v_stage in select * from jsonb_array_elements(p_stages) loop
    v_ord  := v_ord + 1;
    v_name := nullif(btrim(coalesce(v_stage->>'name', '')), '');
    if v_name is null then
      raise exception 'Stage % has no name.', v_ord;
    end if;
    v_disc := nullif(btrim(coalesce(v_stage->>'discipline', '')), '')::user_role;

    insert into template_stages (template_id, name, ord, step, default_duration_days, discipline)
    values (v_tpl, v_name, v_ord,
            coalesce((v_stage->>'step')::int, v_ord),
            greatest(coalesce((v_stage->>'days')::int, 1), 1),
            v_disc)
    returning id into v_ts;

    for v_el in select * from jsonb_array_elements(coalesce(v_stage->'items', '[]'::jsonb)) loop
      insert into template_stage_items (template_stage_id, item_catalog_id, qty)
      values (v_ts, (v_el->>'item_catalog_id')::uuid,
              greatest(coalesce((v_el->>'qty')::int, 1), 1));
    end loop;

    v_i := 0;
    for v_el in select * from jsonb_array_elements(coalesce(v_stage->'checks', '[]'::jsonb)) loop
      continue when nullif(btrim(coalesce(v_el->>'label', '')), '') is null;
      insert into template_stage_checks (template_stage_id, label, ord, photo_required)
      values (v_ts, btrim(v_el->>'label'), v_i,
              coalesce((v_el->>'photo_required')::boolean, false));
      v_i := v_i + 1;
    end loop;

    v_i := 0;
    for v_el in select * from jsonb_array_elements(coalesce(v_stage->'tasks', '[]'::jsonb)) loop
      continue when nullif(btrim(coalesce(v_el->>'title', '')), '') is null;
      v_i := v_i + 1;
      insert into template_stage_tasks (template_stage_id, title, ord, step)
      values (v_ts, btrim(v_el->>'title'), v_i,
              coalesce((v_el->>'step')::int, v_i));
    end loop;
  end loop;

  perform public.fn_audit('create_template', 'workflow_template', v_tpl);
  return v_tpl;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. Onboarding copies the breakdown onto the build
--
-- Body is 0031's, extracted verbatim, with step 1c added after the checklist
-- copy. Nothing else in it changes.
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

  -- 1b) checklist for each stage, carrying the template's photo rule (0029).
  insert into checklist_items (stage_id, label, done, photo_required)
  select s.id, tsc.label, false, coalesce(tsc.photo_required, false)
    from template_stage_checks tsc
    join stages s on s.template_stage_id = tsc.template_stage_id
                 and s.project_id = p_project
   where not exists (select 1 from checklist_items ci where ci.stage_id = s.id)
   order by tsc.ord;

  -- 1c) the workshop breakdown, as unassigned work items (0034). The
  --     supervisor gives each one to somebody; until then they are the plan.
  insert into stage_tasks (stage_id, title, ord, step)
  select s.id, tst.title, tst.ord, coalesce(tst.step, tst.ord)
    from template_stage_tasks tst
    join stages s on s.template_stage_id = tst.template_stage_id
                 and s.project_id = p_project
   where not exists (select 1 from stage_tasks st where st.stage_id = s.id)
   order by tst.ord;

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

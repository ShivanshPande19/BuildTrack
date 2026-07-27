-- Azimuth BuildTrack — Bill of Materials + auto-generated requirements (Hero #1)
-- Closes the gap: onboarding now auto-creates procurement requirements from a
-- template's BOM, with needed_by = the backward-scheduled planned_start of the
-- consuming stage. Requirements stay fully editable per project afterwards.

-- ========== BOM: which catalog items each template stage needs ==========
create table if not exists template_stage_items (
  id                uuid primary key default gen_random_uuid(),
  template_stage_id uuid not null references template_stages(id) on delete cascade,
  item_catalog_id   uuid not null references item_catalog(id),
  qty               int  not null default 1
);
create index if not exists idx_tsi_stage on template_stage_items(template_stage_id);

alter table template_stage_items enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='template_stage_items' and policyname='tsi_staff') then
    create policy tsi_staff on template_stage_items
      for all using (public.is_staff()) with check (public.is_staff());
  end if;
end $$;

-- ========== onboarding now also generates requirements from the BOM ==========
create or replace function public.fn_onboard_project(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_template uuid;
begin
  select template_id into v_template from projects where id = p_project;
  if v_template is null then return; end if;

  -- 1) stages from template (idempotent)
  insert into stages (project_id, template_stage_id, name, ord, status)
  select p_project, ts.id, ts.name, ts.ord, 'todo'
  from template_stages ts
  where ts.template_id = v_template
    and not exists (select 1 from stages s where s.project_id = p_project);

  -- 2) backward-schedule the stages (fills planned_start / planned_end)
  perform public.fn_recompute_schedule(p_project);

  -- 3) auto-generate requirements from the BOM (idempotent), needed_by = stage start
  if not exists (select 1 from procurement_requirements where project_id = p_project) then
    insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, status)
    select p_project, tsi.item_catalog_id, tsi.qty, s.planned_start, 'pending'
    from template_stage_items tsi
    join stages s on s.template_stage_id = tsi.template_stage_id and s.project_id = p_project;
  end if;

  -- 4) recompute order_by dates now that requirements exist
  perform public.fn_recompute_schedule(p_project);
  perform public.fn_recompute_progress(p_project);
end $$;

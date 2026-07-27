-- ============================================================================
-- DEMO DATA — Stage details (photos + installed parts + checklist)
-- Purpose: make the "View details" (Stage detail) screen testable BEFORE the
-- Store / Workshop / Design roles are built. When those roles ship, real rows
-- replace this demo data automatically (same tables).
--
-- Safe to run once in Supabase SQL editor. Idempotent (guards on a demo serial).
-- ============================================================================
do $$
declare
  v_proj         uuid;
  v_stage_a      uuid;   -- first stage (structure/chassis)
  v_stage_b      uuid;   -- a later stage (electrical/interior)
  v_item         uuid;
  v_vendor       uuid;
begin
  -- already seeded? bail out
  if exists (select 1 from component_instances where serial_number = 'SN-DEMO-0001') then
    raise notice 'Stage demo data already present — skipping.';
    return;
  end if;

  select id into v_proj from projects order by code asc limit 1;
  if v_proj is null then
    raise notice 'No projects found — onboard a project first.';
    return;
  end if;

  select id into v_stage_a from stages where project_id = v_proj order by ord asc limit 1;
  select id into v_stage_b from stages where project_id = v_proj order by ord asc offset 2 limit 1;
  if v_stage_b is null then v_stage_b := v_stage_a; end if;

  select id into v_item   from item_catalog limit 1;
  select id into v_vendor from vendors limit 1;

  -- checklist on the first stage
  insert into checklist_items (stage_id, label, done) values
    (v_stage_a, 'Chassis welded & squared',   true),
    (v_stage_a, 'Floor frame mounted',         true),
    (v_stage_a, 'Wall studs fixed & braced',   false),
    (v_stage_a, 'Roof ribs installed',         false);

  -- photos (attachments, owner_type = 'stage')
  insert into attachments (owner_type, owner_id, file_url, caption) values
    ('stage', v_stage_a, 'https://picsum.photos/seed/chassis1/600/400', 'Chassis frame welded'),
    ('stage', v_stage_a, 'https://picsum.photos/seed/chassis2/600/400', 'Floor frame mounted'),
    ('stage', v_stage_b, 'https://picsum.photos/seed/interior1/600/400', 'Wiring loom run'),
    ('stage', v_stage_b, 'https://picsum.photos/seed/interior2/600/400', 'Panels fitted');

  -- installed parts (component_instances → traceability)
  if v_item is not null and v_vendor is not null then
    insert into component_instances
      (item_catalog_id, serial_number, vendor_id, status,
       installed_in_project_id, installed_stage_id, warranty_start, warranty_end, install_date)
    values
      (v_item, 'SN-DEMO-0001', v_vendor, 'installed', v_proj, v_stage_b, current_date, current_date + 730, current_date),
      (v_item, 'SN-DEMO-0002', v_vendor, 'installed', v_proj, v_stage_b, current_date, current_date + 365, current_date);
  end if;

  raise notice 'Stage demo data inserted for project %.', v_proj;
end $$;

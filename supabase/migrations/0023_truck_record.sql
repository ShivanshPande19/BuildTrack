-- 0023_truck_record.sql
--
-- Per-truck complete record (Phase 3). Every component ever installed on a build
-- already lives in component_instances with its serial, bill, warranty, the
-- stage it went into and who installed it (Hero #2). This view pulls that into
-- one place per truck so the admin can see a build's whole physical record —
-- materials, equipment, serials, warranties and bills — without hunting stage by
-- stage.
--
-- Read model only; no new tables.

drop view if exists public.v_truck_components;
create view public.v_truck_components with (security_invoker = on) as
  select
    ci.id,
    ci.installed_in_project_id as project_id,
    ic.name  as item_name,
    ic.model,
    ci.serial_number,
    v.name   as vendor_name,
    ci.bill_url,
    ci.warranty_start,
    ci.warranty_end,
    ci.status,
    s.name       as stage_name,
    s.discipline as stage_discipline,
    s.ord        as stage_ord,
    inst.full_name as installed_by_name,
    ci.install_date
  from component_instances ci
  join item_catalog ic on ic.id = ci.item_catalog_id
  left join vendors  v    on v.id    = ci.vendor_id
  left join stages   s    on s.id    = ci.installed_stage_id
  left join profiles inst on inst.id = ci.installed_by
  where ci.installed_in_project_id is not null;

grant select on public.v_truck_components to authenticated;

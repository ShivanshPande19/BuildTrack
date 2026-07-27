-- ============================================================================
-- DEMO — attach a Bill of Materials to the first workflow template, so that
-- onboarding a NEW project auto-generates procurement requirements (Hero #1).
-- Run AFTER 0005_bom.sql. Idempotent. Safe in Supabase SQL editor.
-- ============================================================================
do $$
declare
  v_tmpl       uuid;
  v_stage_a    uuid;
  v_stage_b    uuid;
begin
  select id into v_tmpl from workflow_templates order by name asc limit 1;
  if v_tmpl is null then raise notice 'No template found.'; return; end if;

  if exists (
    select 1 from template_stage_items tsi
    join template_stages ts on ts.id = tsi.template_stage_id
    where ts.template_id = v_tmpl
  ) then raise notice 'BOM demo already present.'; return; end if;

  -- pick two later stages (fall back to the first stage if the template is short)
  select id into v_stage_a from template_stages where template_id = v_tmpl order by ord offset 3 limit 1;
  select id into v_stage_b from template_stages where template_id = v_tmpl order by ord offset 4 limit 1;
  if v_stage_a is null then select id into v_stage_a from template_stages where template_id = v_tmpl order by ord asc limit 1; end if;
  if v_stage_b is null then v_stage_b := v_stage_a; end if;

  -- attach up to 3 catalog items across those stages (guarded selects: 0 or 1 row each)
  insert into template_stage_items (template_stage_id, item_catalog_id, qty)
  select v_stage_a, id, 1 from item_catalog order by name asc limit 1;

  insert into template_stage_items (template_stage_id, item_catalog_id, qty)
  select v_stage_b, id, 1 from item_catalog order by name asc offset 1 limit 1;

  insert into template_stage_items (template_stage_id, item_catalog_id, qty)
  select v_stage_b, id, 2 from item_catalog order by name asc offset 2 limit 1;

  raise notice 'BOM demo attached to template %. Onboard a NEW project to see auto-generated requirements.', v_tmpl;
end $$;

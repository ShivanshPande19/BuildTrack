-- ============================================================================
-- Which migrations are applied on THIS database?
--
-- READ-ONLY. Safe to run at any time in the Supabase SQL editor.
-- Each row says "applied" or "RUN THIS". Run the "RUN THIS" migrations from
-- supabase/migrations/ one file at a time, in number order. If one errors, stop
-- there; don't skip ahead.
--
-- Each check looks for an object that ONLY that migration creates (a table,
-- function, policy, column, bucket, or text inside a replaced function body).
-- 0001-0003 are the base schema; if they were missing, nothing here would run.
--
-- Before 0025: it adds a UNIQUE index on design_versions(artifact_id, version_no),
-- so this must return 0 rows first:
--   select artifact_id, version_no, count(*) from design_versions
--   group by 1, 2 having count(*) > 1;
--
-- Don't re-run 0019 (it resets every bulk item to essential) and don't re-run
-- 0020 after 0021 (it re-creates the old v_po_pending_approvals).
-- ============================================================================
with checks(migration, applied) as (values
  ('0004_onboarding',
     exists (select 1 from pg_proc where proname = 'fn_onboard_project')),
  ('0005_bom',
     to_regclass('public.template_stage_items') is not null),
  ('0006_client_attachments',
     exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attachments'
               and policyname = 'p_att_client')),
  ('0007_design_model',
     exists (select 1 from information_schema.columns where table_schema = 'public'
               and table_name = 'design_versions' and column_name = 'model_url')),
  ('0008_design_storage',
     exists (select 1 from storage.buckets where id = 'designs')),
  ('0009_workflow',
     exists (select 1 from pg_proc where proname = 'fn_assign_stage')),
  ('0010_service',
     exists (select 1 from pg_proc where proname = 'fn_mark_delivered')),
  ('0011_builds_storage',
     exists (select 1 from storage.buckets where id = 'builds')),
  ('0012_template_checklists',
     to_regclass('public.template_stage_checks') is not null),
  ('0013_stock_movement',
     exists (select 1 from pg_proc where proname = 'fn_receive_po' and prosrc ilike '%stock_items%')),
  ('0014_client_ticket_visibility',
     exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tickets'
               and policyname = 'p_tickets_client_project')),
  ('0015_rebaseline_on_delivery_change',
     exists (select 1 from pg_proc where proname = 'fn_recompute_schedule'
               and 'p_rebaseline_assigned' = any (proargnames))),
  ('0016_receive_requires_dispatch',
     exists (select 1 from pg_proc where proname = 'fn_receive_po'
               and prosrc ilike '%dispatched before receiving%')),
  ('0017_stock_requests',
     to_regclass('public.stock_requests') is not null
     and exists (select 1 from pg_proc where proname = 'fn_request_stock')),
  ('0018_intake_serialized',
     exists (select 1 from pg_proc where proname = 'fn_receive_po' and prosrc ilike '%serialized = false%')),
  ('0019_essential_items',
     exists (select 1 from information_schema.columns where table_schema = 'public'
               and table_name = 'item_catalog' and column_name = 'is_essential')),
  ('0020_po_approvals',
     to_regclass('public.po_approval_events') is not null
     and exists (select 1 from pg_proc where proname = 'fn_create_po')),
  ('0021_ops_command_center',
     to_regclass('public.sub_teams') is not null and to_regclass('public.v_ops_board') is not null),
  ('0022_project_delays',
     to_regclass('public.v_project_delays') is not null),
  ('0023_truck_record',
     to_regclass('public.v_truck_components') is not null),
  ('0024_status_delivery_date',
     exists (select 1 from pg_proc where proname = 'fn_recompute_status'
               and prosrc ilike '%target_delivery_date%')),
  ('0025_design_version_atomic',
     exists (select 1 from pg_proc where proname = 'fn_add_design_version')
     and to_regclass('public.ux_design_versions_artifact_no') is not null)
)
select migration,
       case when applied then 'applied' else 'RUN THIS' end as status
  from checks
 order by migration;

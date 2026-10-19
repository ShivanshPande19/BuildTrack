-- Azimuth BuildTrack — complete backend setup (schema · RLS · functions · seed)
--
-- GENERATED FILE — do not edit by hand.
-- Regenerate with:  cd supabase && sh build_full_setup.sh
-- Source of truth:  migrations/*.sql applied in order, then seed.sql.
--
-- Run this once on a fresh Supabase project (SQL editor), or apply the
-- migrations individually if the project already has some of them.


-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0001_init.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — schema (Supabase / Postgres 15)
-- Derived from BuildTrack_DataModel.md

-- ========== ENUMS ==========
create type user_role        as enum ('admin','pm','procurement','workshop','store','design','service','client');
create type project_status   as enum ('on_track','at_risk','delayed','delivered');
create type stage_status     as enum ('todo','in_progress','done','rework');
create type delay_reason     as enum ('procurement','design_approval','workshop_capacity','weather','client','quality','other');
create type po_status        as enum ('ordered','dispatched','received','partial');
create type req_status        as enum ('pending','ordered','received');
create type component_status as enum ('in_stock','installed','replaced','faulty');
create type design_type      as enum ('layout','interior','exterior','branding');
create type design_status    as enum ('draft','pending_approval','revision','approved');
create type approval_status  as enum ('pending','approved','changes_requested','rejected');
create type ticket_category  as enum ('equipment','electrical','cosmetic','other');
create type ticket_status    as enum ('open','in_progress','resolved','closed');
create type ticket_priority  as enum ('low','medium','high');
create type resolution_type  as enum ('warranty_replace','repair','remote_guide');
create type visit_status     as enum ('scheduled','done','cancelled');
create type grn_status       as enum ('complete','partial','issue');
create type doc_type         as enum ('contract','invoice','warranty_pack','handover_cert');
create type user_status      as enum ('active','invited','disabled');

-- ========== IDENTITY ==========
create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  full_name    text not null,
  email        text unique not null,
  phone        text,
  role         user_role not null,
  avatar_color text,
  status       user_status not null default 'invited',
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now()
);

create table client_accounts (
  id              uuid primary key default gen_random_uuid(),
  business_name   text not null,
  contact_user_id uuid references profiles(id),
  phone           text,
  email           text
);

-- ========== TEMPLATES ==========
create table workflow_templates (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  truck_type text
);

create table template_stages (
  id                    uuid primary key default gen_random_uuid(),
  template_id           uuid not null references workflow_templates(id) on delete cascade,
  name                  text not null,
  ord                   int  not null,
  default_duration_days int  not null default 1,
  depends_on            uuid references template_stages(id)
);

-- ========== PROJECTS & BUILD ==========
create table projects (
  id                   uuid primary key default gen_random_uuid(),
  code                 text unique not null,
  name                 text not null,
  client_account_id    uuid references client_accounts(id),
  template_id          uuid references workflow_templates(id),
  pm_id                uuid references profiles(id),
  status               project_status not null default 'on_track',
  progress_pct         int not null default 0,
  current_stage_id     uuid,               -- FK added after stages
  target_delivery_date date,
  actual_delivery_date date,
  advance_received     boolean not null default false,
  created_at           timestamptz not null default now()
);

create table bays (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  current_stage_id uuid
);

create table stages (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null references projects(id) on delete cascade,
  template_stage_id uuid references template_stages(id),
  name              text not null,
  ord               int  not null,
  planned_start     date,
  planned_end       date,
  actual_start      date,
  actual_end        date,
  status            stage_status not null default 'todo',
  assignee_id       uuid references profiles(id),
  bay_id            uuid references bays(id)
);
create index idx_stages_project on stages(project_id);

alter table projects add constraint fk_current_stage foreign key (current_stage_id) references stages(id);
alter table bays     add constraint fk_bay_stage     foreign key (current_stage_id) references stages(id);

create table checklist_items (
  id       uuid primary key default gen_random_uuid(),
  stage_id uuid not null references stages(id) on delete cascade,
  label    text not null,
  done     boolean not null default false
);

create table delay_logs (
  id           uuid primary key default gen_random_uuid(),
  stage_id     uuid not null references stages(id) on delete cascade,
  reason_code  delay_reason not null,
  days_delayed int not null default 0,
  note         text,
  logged_by    uuid references profiles(id),
  created_at   timestamptz not null default now()
);

-- ========== PROCUREMENT ==========
create table vendors (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  category           text,
  avg_lead_time_days int default 0,
  reliability_score  int default 100,
  contact            text
);

create table item_catalog (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  model               text,
  category            text,
  default_vendor_id   uuid references vendors(id),
  lead_time_days      int not null default 0,
  buffer_days         int not null default 1,
  serialized          boolean not null default true,
  unit                text default 'pcs',
  low_stock_threshold int default 0
);

create table purchase_orders (
  id            uuid primary key default gen_random_uuid(),
  po_number     text unique not null,
  vendor_id     uuid references vendors(id),
  project_id    uuid references projects(id),
  status        po_status not null default 'ordered',
  order_date    date,
  expected_date date,
  created_by    uuid references profiles(id)
);

create table procurement_requirements (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references projects(id) on delete cascade,
  item_catalog_id uuid not null references item_catalog(id),
  qty             int not null default 1,
  needed_by_date  date,
  order_by_date   date,                    -- computed = needed_by - lead - buffer
  status          req_status not null default 'pending',
  po_id           uuid references purchase_orders(id)
);
create index idx_req_orderby on procurement_requirements(order_by_date, status);

create table po_lines (
  id              uuid primary key default gen_random_uuid(),
  po_id           uuid not null references purchase_orders(id) on delete cascade,
  item_catalog_id uuid not null references item_catalog(id),
  qty             int not null default 1,
  received_qty    int not null default 0
);

create table goods_receipts (
  id          uuid primary key default gen_random_uuid(),
  po_id       uuid references purchase_orders(id),
  received_by uuid references profiles(id),
  received_at timestamptz not null default now(),
  status      grn_status not null default 'complete',
  note        text
);

-- ========== INVENTORY & TRACEABILITY ==========
create table component_instances (
  id                     uuid primary key default gen_random_uuid(),
  item_catalog_id        uuid not null references item_catalog(id),
  serial_number          text unique,
  vendor_id              uuid references vendors(id),
  grn_id                 uuid references goods_receipts(id),
  bill_url               text,                       -- Store captures at intake
  warranty_start         date,
  warranty_end           date,
  status                 component_status not null default 'in_stock',
  installed_in_project_id uuid references projects(id),
  installed_stage_id     uuid references stages(id),
  installed_by           uuid references profiles(id),
  install_date           date
);
create index idx_comp_model   on component_instances(item_catalog_id);
create index idx_comp_project on component_instances(installed_in_project_id);

create table stock_items (
  id              uuid primary key default gen_random_uuid(),
  item_catalog_id uuid not null references item_catalog(id),
  quantity        numeric not null default 0,
  unit            text default 'pcs'
);

-- ========== DESIGN ==========
create table design_artifacts (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references projects(id) on delete cascade,
  type               design_type not null,
  status             design_status not null default 'draft',
  current_version_id uuid,
  created_by         uuid references profiles(id)
);

create table design_versions (
  id          uuid primary key default gen_random_uuid(),
  artifact_id uuid not null references design_artifacts(id) on delete cascade,
  version_no  int not null default 1,
  file_url    text,
  change_note text,
  created_at  timestamptz not null default now()
);
alter table design_artifacts add constraint fk_current_version foreign key (current_version_id) references design_versions(id);

create table design_approvals (
  id             uuid primary key default gen_random_uuid(),
  version_id     uuid not null references design_versions(id) on delete cascade,
  client_user_id uuid references profiles(id),
  status         approval_status not null default 'pending',
  feedback       text,
  decided_at     timestamptz
);

-- ========== SERVICE ==========
create table tickets (
  id                  uuid primary key default gen_random_uuid(),
  ticket_number       text unique not null,
  project_id          uuid references projects(id),
  raised_by           uuid references profiles(id),
  category            ticket_category not null default 'other',
  description         text,
  linked_component_id uuid references component_instances(id),
  priority            ticket_priority not null default 'medium',
  sla_due             timestamptz,
  status              ticket_status not null default 'open',
  assigned_to         uuid references profiles(id),
  resolution_type     resolution_type,
  resolution_note     text,
  created_at          timestamptz not null default now(),
  resolved_at         timestamptz
);

create table service_visits (
  id             uuid primary key default gen_random_uuid(),
  ticket_id      uuid not null references tickets(id) on delete cascade,
  technician_id  uuid references profiles(id),
  scheduled_date timestamptz,
  status         visit_status not null default 'scheduled'
);

-- ========== CROSS-CUTTING ==========
create table stage_approvals (
  id           uuid primary key default gen_random_uuid(),
  stage_id     uuid not null references stages(id) on delete cascade,
  submitted_by uuid references profiles(id),
  approver_id  uuid references profiles(id),
  status       approval_status not null default 'pending',
  decided_at   timestamptz
);

create table attachments (
  id          uuid primary key default gen_random_uuid(),
  owner_type  text not null,      -- stage | ticket | component | design_version
  owner_id    uuid not null,
  file_url    text not null,
  caption     text,
  uploaded_by uuid references profiles(id),
  created_at  timestamptz not null default now()
);

create table documents (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  type       doc_type not null,
  file_url   text,
  available  boolean not null default false
);

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  type        text,
  title       text not null,
  body        text,
  entity_type text,
  entity_id   uuid,
  read        boolean not null default false,
  created_at  timestamptz not null default now()
);
create index idx_notif_user on notifications(user_id, read);

create table audit_log (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references profiles(id),
  action      text not null,
  entity_type text,
  entity_id   uuid,
  created_at  timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0002_rls.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — Row Level Security (role permission matrix, enforced in DB)

-- ===== helpers =====
create or replace function public.my_role() returns user_role
  language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() $$;

create or replace function public.is_admin() returns boolean
  language sql stable as $$ select public.my_role() = 'admin' $$;

create or replace function public.is_staff() returns boolean
  language sql stable as $$ select coalesce(public.my_role() <> 'client', false) $$;

create or replace function public.my_client_account() returns uuid
  language sql stable security definer set search_path = public as
$$ select id from client_accounts where contact_user_id = auth.uid() limit 1 $$;

-- enable RLS on everything
do $$ declare t text;
begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ===== profiles =====
create policy p_profiles_read on profiles for select using (auth.uid() is not null);
create policy p_profiles_admin on profiles for all using (public.is_admin()) with check (public.is_admin());

-- ===== staff-only operational tables (clients blocked) =====
-- vendors, item_catalog, stock_items, purchase_orders, po_lines, goods_receipts,
-- procurement_requirements, workflow_templates, template_stages, bays, delay_logs,
-- stage_approvals, service_visits, audit_log, component_instances
do $$ declare t text;
begin
  foreach t in array array[
    'vendors','item_catalog','stock_items','purchase_orders','po_lines','goods_receipts',
    'procurement_requirements','workflow_templates','template_stages','bays','delay_logs',
    'stage_approvals','service_visits','audit_log','component_instances'
  ] loop
    execute format('create policy %I on public.%I for all using (public.is_staff()) with check (public.is_staff())', t||'_staff', t);
  end loop;
end $$;

-- ===== projects =====  staff read all; client reads own; admin/pm write
create policy p_projects_staff  on projects for select using (public.is_staff());
create policy p_projects_client on projects for select using (client_account_id = public.my_client_account());
create policy p_projects_write  on projects for all
  using (public.is_admin() or pm_id = auth.uid())
  with check (public.is_admin() or pm_id = auth.uid());

-- ===== stages / checklist =====  staff all; client read own project
create policy p_stages_staff  on stages for all using (public.is_staff()) with check (public.is_staff());
create policy p_stages_client on stages for select using (
  exists (select 1 from projects p where p.id = stages.project_id and p.client_account_id = public.my_client_account()));
create policy p_check_staff on checklist_items for all using (public.is_staff()) with check (public.is_staff());

-- ===== designs =====  staff all; client read own project + act on approvals
create policy p_design_staff  on design_artifacts for all using (public.is_staff()) with check (public.is_staff());
create policy p_design_client on design_artifacts for select using (
  exists (select 1 from projects p where p.id = design_artifacts.project_id and p.client_account_id = public.my_client_account()));
create policy p_dver_staff  on design_versions for all using (public.is_staff()) with check (public.is_staff());
create policy p_dver_client on design_versions for select using (
  exists (select 1 from design_artifacts a join projects p on p.id=a.project_id
          where a.id = design_versions.artifact_id and p.client_account_id = public.my_client_account()));
create policy p_dappr_staff  on design_approvals for all using (public.is_staff()) with check (public.is_staff());
create policy p_dappr_client on design_approvals for all
  using (client_user_id = auth.uid()) with check (client_user_id = auth.uid());

-- ===== tickets =====  service staff all; client own
create policy p_tickets_staff  on tickets for all using (public.is_staff()) with check (public.is_staff());
create policy p_tickets_client on tickets for select using (raised_by = auth.uid());
create policy p_tickets_client_new on tickets for insert with check (raised_by = auth.uid());

-- ===== documents =====  staff all; client read own available docs
create policy p_docs_staff  on documents for all using (public.is_staff()) with check (public.is_staff());
create policy p_docs_client on documents for select using (
  available and exists (select 1 from projects p where p.id = documents.project_id and p.client_account_id = public.my_client_account()));

-- ===== attachments =====  staff all; client read attachments on own tickets
create policy p_att_staff on attachments for all using (public.is_staff()) with check (public.is_staff());

-- ===== notifications =====  each user their own
create policy p_notif_own on notifications for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ===== client_accounts =====  staff all; client reads own
create policy p_ca_staff  on client_accounts for all using (public.is_staff()) with check (public.is_staff());
create policy p_ca_client on client_accounts for select using (contact_user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0003_functions.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — core logic functions

-- ============================================================
-- Backward scheduling (Hero #1): from a project's target_delivery_date,
-- lay out stage planned dates in reverse, then compute each
-- procurement requirement's order_by_date.
-- (MVP: calendar days; holidays/weekends can be layered later.)
-- ============================================================
create or replace function public.fn_recompute_schedule(p_project uuid)
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
  -- walk stages from last to first
  for r in
    select s.id, coalesce(ts.default_duration_days, 1) as dur
    from stages s
    left join template_stages ts on ts.id = s.template_stage_id
    where s.project_id = p_project
    order by s.ord desc
  loop
    v_dur := greatest(r.dur, 1);
    update stages
       set planned_end   = v_cursor,
           planned_start = v_cursor - (v_dur - 1)
     where id = r.id;
    v_cursor := (v_cursor - v_dur);  -- day before this stage starts
  end loop;

  -- order-by date for each requirement = needed_by - lead - buffer
  update procurement_requirements pr
     set order_by_date = pr.needed_by_date - ic.lead_time_days - ic.buffer_days
    from item_catalog ic
   where pr.item_catalog_id = ic.id
     and pr.project_id = p_project
     and pr.needed_by_date is not null;
end $$;

-- ============================================================
-- Recompute project % + status from stages
-- ============================================================
create or replace function public.fn_recompute_progress(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_total int; v_done int; v_pct int;
begin
  select count(*), count(*) filter (where status = 'done')
    into v_total, v_done from stages where project_id = p_project;
  v_pct := case when v_total > 0 then round(100.0 * v_done / v_total) else 0 end;
  update projects set progress_pct = v_pct where id = p_project;
end $$;

-- keep progress fresh whenever a stage changes
create or replace function public.trg_stage_progress() returns trigger
language plpgsql as $$
begin
  perform public.fn_recompute_progress(coalesce(new.project_id, old.project_id));
  return null;
end $$;

create trigger t_stage_progress
after insert or update of status or delete on stages
for each row execute function public.trg_stage_progress();

-- ============================================================
-- Requirements that must be ordered soon (drives "To-Order" alerts)
-- ============================================================
create or replace view public.v_order_due as
  select pr.*, ic.name as item_name, p.code as project_code,
         (pr.order_by_date - current_date) as days_left
  from procurement_requirements pr
  join item_catalog ic on ic.id = pr.item_catalog_id
  join projects p on p.id = pr.project_id
  where pr.status = 'pending'
  order by pr.order_by_date asc;

-- ============================================================
-- Recall (Hero #2): every truck that has a given item model installed
-- ============================================================
create or replace function public.fn_recall(p_item uuid)
returns table(project_id uuid, project_code text, serial text, status component_status)
language sql stable as $$
  select ci.installed_in_project_id, p.code, ci.serial_number, ci.status
  from component_instances ci
  join projects p on p.id = ci.installed_in_project_id
  where ci.item_catalog_id = p_item
    and ci.installed_in_project_id is not null;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0004_onboarding.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — project onboarding
-- Called after inserting a project row: generates its stages from the template
-- and backward-schedules everything. Idempotent (won't duplicate stages).

create or replace function public.fn_onboard_project(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_template uuid;
begin
  select template_id into v_template from projects where id = p_project;
  if v_template is null then return; end if;

  insert into stages (project_id, template_stage_id, name, ord, status)
  select p_project, ts.id, ts.name, ts.ord, 'todo'
  from template_stages ts
  where ts.template_id = v_template
    and not exists (select 1 from stages s where s.project_id = p_project);

  perform public.fn_recompute_schedule(p_project);
  perform public.fn_recompute_progress(p_project);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0005_bom.sql
-- ═══════════════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0006_client_attachments.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — let a client read the build photos of their own trucks.
-- attachments had only a staff policy; clients need read access to stage photos
-- on projects that belong to their client_account.

do $$ begin
  if not exists (select 1 from pg_policies where tablename='attachments' and policyname='p_att_client') then
    create policy p_att_client on attachments for select using (
      owner_type = 'stage' and exists (
        select 1 from stages s
        join projects p on p.id = s.project_id
        where s.id = attachments.owner_id
          and p.client_account_id = public.my_client_account()
      )
    );
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0007_design_model.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0007_design_model.sql
-- Designer role support:
--  • design_versions.model_url  — the approved 3D model (.glb) shown in the app
--    (client My Trucks card + admin/PM project detail). file_url stays the 2D
--    image/preview; model_url is specifically the glTF-Binary model.
--  • design_artifacts.client_feedback — the note a client leaves when they tap
--    "Request changes", so the designer knows exactly what to fix.

alter table design_versions  add column if not exists model_url      text;
alter table design_artifacts add column if not exists client_feedback text;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0008_design_storage.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0008_design_storage.sql
-- Self-serve design uploads: a public 'designs' bucket where designers upload
-- their .glb models + 2D preview images straight from the app. Public read so
-- <model-viewer> can fetch the .glb; only staff can upload/replace.

insert into storage.buckets (id, name, public)
values ('designs', 'designs', true)
on conflict (id) do nothing;

-- Anyone can read (needed for the public 3D preview URL).
drop policy if exists "designs public read" on storage.objects;
create policy "designs public read" on storage.objects
  for select using (bucket_id = 'designs');

-- Only signed-in staff can upload / replace / remove design files.
drop policy if exists "designs staff insert" on storage.objects;
create policy "designs staff insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'designs' and public.is_staff());

drop policy if exists "designs staff update" on storage.objects;
create policy "designs staff update" on storage.objects
  for update to authenticated
  using (bucket_id = 'designs' and public.is_staff())
  with check (bucket_id = 'designs' and public.is_staff());

drop policy if exists "designs staff delete" on storage.objects;
create policy "designs staff delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'designs' and public.is_staff());

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0009_workflow.sql
-- ═══════════════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0010_service.sql
-- ═══════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0010_service.sql — Service role (post-delivery support)
--
-- The tables for after-sales existed since 0001 but nothing ever used them:
-- tickets had no SLA and no consumer, service_visits was never written, and no
-- truck could even reach 'delivered' because nothing set actual_delivery_date.
-- This wires the whole after-sales loop:
--
--   PM      marks a build delivered  ──►  it enters service
--   Client  raises a request         ──►  every service member is notified
--   Service triages, assigns a technician, schedules a visit
--   Service resolves (warranty replace / repair / remote guide)  ──►  client told
--
-- Same architecture as 0009: rules live here as SECURITY DEFINER RPCs so they
-- hold no matter what calls them. Safe to re-run (idempotent).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1. SCHEMA — the few columns the after-sales loop was missing
-- ════════════════════════════════════════════════════════════════════════════

-- Ticket numbers were generated in Dart ('R-<millis>'), so they were neither
-- stable nor sequential. A sequence makes them predictable: T-001, T-002 …
create sequence if not exists ticket_number_seq start 1;

alter table tickets add column if not exists closed_at    timestamptz;
alter table tickets add column if not exists first_reply_at timestamptz;

-- A visit needs a note (what to bring / what was found) and an audit trail.
alter table service_visits add column if not exists note       text;
alter table service_visits add column if not exists created_at timestamptz not null default now();
alter table service_visits add column if not exists created_by uuid references profiles(id) on delete set null;

create index if not exists idx_tickets_status   on tickets(status, sla_due);
create index if not exists idx_tickets_project  on tickets(project_id);
create index if not exists idx_tickets_assignee on tickets(assigned_to);
create index if not exists idx_visits_ticket    on service_visits(ticket_id);
create index if not exists idx_comp_warranty    on component_instances(warranty_end);


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Notify a whole role (the missing piece that left client tickets unheard)
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_notify_role(
  p_roles text[], p_type text, p_title text,
  p_body text default null, p_entity_type text default null, p_entity_id uuid default null,
  p_exclude uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select id from profiles
     where role::text = any(p_roles)
       and status <> 'disabled'
       and (p_exclude is null or id <> p_exclude)
  loop
    perform public.fn_notify(r.id, p_type, p_title, p_body, p_entity_type, p_entity_id);
    n := n + 1;
  end loop;
  return n;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. SLA — every ticket gets a deadline the moment it is raised
--    high = 4h · medium = 24h · low = 72h
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_sla_hours(p_priority ticket_priority)
returns int language sql immutable as $$
  select case p_priority when 'high' then 4 when 'medium' then 24 else 72 end
$$;

-- Fills in the ticket number and the SLA deadline for *any* insert path — the
-- client's "Raise a request" screen and Service's own "New ticket" alike.
create or replace function public.trg_ticket_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ticket_number is null or btrim(new.ticket_number) = '' then
    new.ticket_number := 'T-' || lpad(nextval('ticket_number_seq')::text, 3, '0');
  end if;
  if new.sla_due is null then
    new.sla_due := now() + (public.fn_sla_hours(new.priority) || ' hours')::interval;
  end if;
  if new.raised_by is null then
    new.raised_by := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists t_ticket_defaults on tickets;
create trigger t_ticket_defaults before insert on tickets
  for each row execute function public.trg_ticket_defaults();

-- ticket_number is NOT NULL, so the trigger has to be able to fill it in.
alter table tickets alter column ticket_number drop not null;

-- A client request that nobody is told about is the same as no request at all.
create or replace function public.trg_ticket_created() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_client text;
begin
  select p.code, ca.business_name into v_code, v_client
    from projects p
    left join client_accounts ca on ca.id = p.client_account_id
   where p.id = new.project_id;

  perform public.fn_notify_role(
    array['service', 'admin'],
    'ticket',
    'New ' || new.priority || '-priority request · ' || coalesce(v_code, 'truck'),
    coalesce(nullif(btrim(coalesce(new.description, '')), ''), new.category::text)
      || coalesce(' — ' || v_client, ''),
    'ticket', new.id,
    new.raised_by);          -- don't notify whoever raised it
  return new;
end $$;

drop trigger if exists t_ticket_created on tickets;
create trigger t_ticket_created after insert on tickets
  for each row execute function public.trg_ticket_created();


-- ════════════════════════════════════════════════════════════════════════════
-- 4. A build enters service only once it is delivered
--    Nothing set actual_delivery_date, so no project could ever reach
--    'delivered' and the Service role had nothing to work with.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_mark_delivered(
  p_project uuid, p_date date default null, p_force boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_code text; v_name text; v_open int; v_delivered date;
begin
  select pm_id, code, name, actual_delivery_date
    into v_pm, v_code, v_name, v_delivered
    from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only this build''s project manager can mark it delivered.' using errcode = '42501';
  end if;
  if v_delivered is not null then
    raise exception 'This build was already delivered on %.', to_char(v_delivered, 'DD Mon YYYY');
  end if;

  select count(*) into v_open from stages
   where project_id = p_project and status <> 'done';
  if v_open > 0 and not p_force then
    raise exception '% stage(s) are still not approved as done. Finish them, or confirm to deliver anyway.', v_open;
  end if;

  update projects
     set actual_delivery_date = coalesce(p_date, current_date)
   where id = p_project;

  perform public.fn_recompute_progress(p_project);   -- flips status to 'delivered'

  perform public.fn_notify_client(p_project, 'delivered',
    v_name || ' is delivered',
    'Your truck is on the road. Any issue from here — raise a request in the app and our service team will pick it up.');

  perform public.fn_notify_role(array['service'], 'delivered',
    v_code || ' is now in service',
    v_name || ' has been delivered and is under warranty support.', 'project', p_project);

  perform public.fn_audit('mark_delivered', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. Service actions
-- ════════════════════════════════════════════════════════════════════════════

-- Service raising a ticket on the client's behalf (phone call, site visit…).
create or replace function public.fn_create_ticket(
  p_project uuid, p_category ticket_category, p_description text,
  p_priority ticket_priority default 'medium', p_component uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can raise a ticket on a client''s behalf.' using errcode = '42501';
  end if;
  if p_project is null then raise exception 'Pick the truck this request is about.'; end if;
  if nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Describe the issue before saving.';
  end if;

  insert into tickets (project_id, category, description, priority, linked_component_id,
                       raised_by, status)
  values (p_project, p_category, btrim(p_description), p_priority, p_component,
          auth.uid(), 'open')
  returning id into v_id;

  return v_id;
end $$;

-- Triage: put a ticket on a technician's plate.
create or replace function public.fn_assign_ticket(p_ticket uuid, p_technician uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_code text; v_role user_role; v_pstatus user_status; v_old uuid; v_status ticket_status;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can assign a ticket.' using errcode = '42501';
  end if;

  select t.ticket_number, t.assigned_to, t.status, p.code
    into v_num, v_old, v_status, v_code
    from tickets t left join projects p on p.id = t.project_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status in ('resolved', 'closed') then
    raise exception 'This ticket is already %.', v_status;
  end if;

  if p_technician is not null then
    select role, status into v_role, v_pstatus from profiles where id = p_technician;
    if v_role is null then raise exception 'That member does not exist.'; end if;
    if v_role not in ('service', 'workshop') then
      raise exception 'Tickets can only go to service or workshop members (that member is %).', v_role;
    end if;
    if v_pstatus = 'disabled' then raise exception 'That member''s account is disabled.'; end if;
  end if;

  update tickets
     set assigned_to = p_technician,
         status = case when p_technician is not null and status = 'open' then 'in_progress'::ticket_status
                       else status end,
         first_reply_at = coalesce(first_reply_at, now())
   where id = p_ticket;

  if p_technician is not null and p_technician is distinct from v_old then
    perform public.fn_notify(p_technician, 'ticket',
      v_num || ' assigned to you',
      'A support request on ' || coalesce(v_code, 'a truck') || ' is now yours.',
      'ticket', p_ticket);
  end if;

  perform public.fn_audit('assign_ticket', 'ticket', p_ticket);
end $$;

-- Book a technician visit. Also moves the ticket to in_progress and tells the client.
create or replace function public.fn_schedule_visit(
  p_ticket uuid, p_technician uuid, p_when timestamptz, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_num text; v_project uuid; v_code text; v_role user_role; v_status ticket_status; v_tech text;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can schedule a visit.' using errcode = '42501';
  end if;
  if p_technician is null then raise exception 'Pick a technician for the visit.'; end if;
  if p_when is null then raise exception 'Pick a date and time for the visit.'; end if;

  select t.ticket_number, t.project_id, t.status, p.code
    into v_num, v_project, v_status, v_code
    from tickets t left join projects p on p.id = t.project_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status in ('resolved', 'closed') then
    raise exception 'This ticket is already %.', v_status;
  end if;

  select role, coalesce(full_name, email) into v_role, v_tech
    from profiles where id = p_technician;
  if v_role is null then raise exception 'That technician does not exist.'; end if;
  if v_role not in ('service', 'workshop') then
    raise exception 'Only service or workshop members can be sent on a visit (that member is %).', v_role;
  end if;

  -- One live booking per ticket: re-scheduling replaces the open one.
  update service_visits set status = 'cancelled'
   where ticket_id = p_ticket and status = 'scheduled';

  insert into service_visits (ticket_id, technician_id, scheduled_date, status, note, created_by)
  values (p_ticket, p_technician, p_when, 'scheduled', nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_id;

  update tickets
     set assigned_to = coalesce(assigned_to, p_technician),
         status = case when status = 'open' then 'in_progress'::ticket_status else status end,
         first_reply_at = coalesce(first_reply_at, now())
   where id = p_ticket;

  perform public.fn_notify(p_technician, 'visit',
    'Visit booked · ' || coalesce(v_code, 'truck'),
    'You are scheduled for ' || to_char(p_when, 'DD Mon, HH12:MI AM') || ' on ' || v_num || '.',
    'ticket', p_ticket);

  perform public.fn_notify_client(v_project, 'visit',
    'Service visit confirmed',
    coalesce(v_tech, 'A technician') || ' will visit on ' || to_char(p_when, 'DD Mon') ||
    ' at ' || to_char(p_when, 'HH12:MI AM') || '.');

  perform public.fn_audit('schedule_visit', 'ticket', p_ticket);
  return v_id;
end $$;

-- Close the loop: how it was fixed, and tell the client.
create or replace function public.fn_resolve_ticket(
  p_ticket uuid, p_resolution resolution_type, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_project uuid; v_status ticket_status; v_raised uuid; v_note text; v_contact uuid;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can resolve a ticket.' using errcode = '42501';
  end if;

  select t.ticket_number, t.project_id, t.status, t.raised_by, ca.contact_user_id
    into v_num, v_project, v_status, v_raised, v_contact
    from tickets t
    left join projects p        on p.id  = t.project_id
    left join client_accounts ca on ca.id = p.client_account_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status in ('resolved', 'closed') then
    raise exception 'This ticket is already %.', v_status;
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is null then
    raise exception 'Add a short note on what was done — the client sees this.';
  end if;

  update tickets
     set status = 'resolved', resolution_type = p_resolution, resolution_note = v_note,
         resolved_at = now(), first_reply_at = coalesce(first_reply_at, now())
   where id = p_ticket;

  -- a booked visit that happened is done, not still pending
  update service_visits set status = 'done'
   where ticket_id = p_ticket and status = 'scheduled';

  perform public.fn_notify_client(v_project, 'resolved',
    v_num || ' resolved',
    v_note);
  -- The raiser may be someone other than the client contact (e.g. a service
  -- member who logged a phoned-in issue) — tell them too, but never send the
  -- client the same notice twice.
  if v_raised is not null
     and v_raised <> auth.uid()
     and v_raised is distinct from v_contact then
    perform public.fn_notify(v_raised, 'resolved', v_num || ' resolved', v_note, 'ticket', p_ticket);
  end if;

  perform public.fn_audit('resolve_ticket', 'ticket', p_ticket);
end $$;

create or replace function public.fn_close_ticket(p_ticket uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status ticket_status;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can close a ticket.' using errcode = '42501';
  end if;
  select status into v_status from tickets where id = p_ticket;
  if v_status is null then raise exception 'Ticket not found.'; end if;
  if v_status = 'closed' then return; end if;
  if v_status <> 'resolved' then
    raise exception 'Resolve the ticket before closing it.';
  end if;
  update tickets set status = 'closed', closed_at = now() where id = p_ticket;
  perform public.fn_audit('close_ticket', 'ticket', p_ticket);
end $$;

-- Client says it isn't actually fixed.
create or replace function public.fn_reopen_ticket(p_ticket uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_status ticket_status; v_assignee uuid; v_reason text;
begin
  select ticket_number, status, assigned_to into v_num, v_status, v_assignee
    from tickets where id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status not in ('resolved', 'closed') then
    raise exception 'This ticket is still open.';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  update tickets
     set status = 'in_progress', resolved_at = null, closed_at = null,
         priority = 'high',                       -- a repeat visit jumps the queue
         sla_due = now() + (public.fn_sla_hours('high') || ' hours')::interval
   where id = p_ticket;

  perform public.fn_notify_role(array['service', 'admin'], 'ticket',
    v_num || ' reopened',
    coalesce(v_reason, 'The issue is not resolved.'), 'ticket', p_ticket, auth.uid());
  perform public.fn_notify(v_assignee, 'ticket', v_num || ' reopened',
    coalesce(v_reason, 'The issue is not resolved.'), 'ticket', p_ticket);

  perform public.fn_audit('reopen_ticket', 'ticket', p_ticket);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. Warranty lookup — search a serial / model / truck and see what's covered
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_warranty_search(p_q text default null)
returns table (
  component_id   uuid,
  item_name      text,
  model          text,
  serial         text,
  project_id     uuid,
  project_code   text,
  vendor_name    text,
  warranty_end   date,
  days_left      int,
  comp_status    text
) language sql stable security definer set search_path = public as $$
  select ci.id,
         coalesce(ic.name, 'Component'),
         coalesce(ic.model, ''),
         coalesce(ci.serial_number, '—'),
         ci.installed_in_project_id,
         coalesce(p.code, ''),
         coalesce(v.name, ''),
         ci.warranty_end,
         case when ci.warranty_end is null then null
              else (ci.warranty_end - current_date) end::int,
         ci.status::text
    from component_instances ci
    left join item_catalog ic on ic.id = ci.item_catalog_id
    left join projects     p  on p.id  = ci.installed_in_project_id
    left join vendors      v  on v.id  = ci.vendor_id
   where public.is_staff()
     and (
       p_q is null or btrim(p_q) = ''
       or ci.serial_number ilike '%' || btrim(p_q) || '%'
       or ic.name          ilike '%' || btrim(p_q) || '%'
       or ic.model         ilike '%' || btrim(p_q) || '%'
       or p.code           ilike '%' || btrim(p_q) || '%'
       or p.name           ilike '%' || btrim(p_q) || '%'
     )
   order by ci.warranty_end nulls last, ci.serial_number
   limit 100
$$;

-- Warranties running out in the next 60 days, newest expiry first — drives the
-- "warranty ending" flag on the delivered-trucks list.
create or replace function public.fn_warranty_expiring(p_days int default 60)
returns table (project_id uuid, project_code text, expiring int, soonest date)
language sql stable security definer set search_path = public as $$
  select ci.installed_in_project_id, coalesce(p.code, ''),
         count(*)::int, min(ci.warranty_end)
    from component_instances ci
    join projects p on p.id = ci.installed_in_project_id
   where public.is_staff()
     and ci.status = 'installed'
     and ci.warranty_end is not null
     and ci.warranty_end between current_date and current_date + p_days
   group by 1, 2
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7. RLS — the client must be able to see how their own request was handled
-- ════════════════════════════════════════════════════════════════════════════

-- Service visits: staff read (0009), admin/service write (0009). A client needs
-- to see the visit booked for their own ticket.
drop policy if exists p_visits_client on service_visits;
create policy p_visits_client on service_visits for select using (
  exists (
    select 1 from tickets t
     where t.id = service_visits.ticket_id
       and t.raised_by = auth.uid()));

-- Let the client reopen their own ticket via fn_reopen_ticket (definer, so no
-- table grant is needed) — but they must not be able to edit tickets directly.
-- 0009's p_tickets_client (select own) and p_tickets_client_new (insert own) stand.


-- ════════════════════════════════════════════════════════════════════════════
-- 8. Backfill — give existing tickets the SLA/number they never had
-- ════════════════════════════════════════════════════════════════════════════

update tickets
   set sla_due = created_at + (public.fn_sla_hours(priority) || ' hours')::interval
 where sla_due is null;

update tickets
   set ticket_number = 'T-' || lpad(nextval('ticket_number_seq')::text, 3, '0')
 where ticket_number is null or btrim(ticket_number) = '';

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0011_builds_storage.sql
-- ═══════════════════════════════════════════════════════════════════════
-- ============================================================================
-- 0011_builds_storage.sql — real photo uploads
--
-- Two placeholders become real:
--   * Workshop "Add photo" attached a random picsum.photos URL — there was no
--     bucket to put an actual site photo in.
--   * The client's "Add a photo" on a support request was a coming-soon snackbar.
--
-- Adds a public 'builds' bucket (same shape as 'designs' in 0008) and lets a
-- client attach photos to their *own* ticket — nothing more.
-- Safe to re-run (idempotent).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1. The bucket
--    Public read, like 'designs': the client's app and the stage gallery load
--    these straight from the URL stored on the attachment row.
-- ════════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('builds', 'builds', true)
on conflict (id) do nothing;

drop policy if exists "builds public read" on storage.objects;
create policy "builds public read" on storage.objects
  for select using (bucket_id = 'builds');

-- Staff upload build photos (workshop progress shots, part close-ups…).
drop policy if exists "builds staff insert" on storage.objects;
create policy "builds staff insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'builds' and public.is_staff());

drop policy if exists "builds staff update" on storage.objects;
create policy "builds staff update" on storage.objects
  for update to authenticated
  using (bucket_id = 'builds' and public.is_staff())
  with check (bucket_id = 'builds' and public.is_staff());

drop policy if exists "builds staff delete" on storage.objects;
create policy "builds staff delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'builds' and public.is_staff());

-- A client may upload, but only under tickets/ — they have no reason to write
-- anywhere else in the bucket.
drop policy if exists "builds client ticket insert" on storage.objects;
create policy "builds client ticket insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'builds'
    and public.my_role() = 'client'
    and (storage.foldername(name))[1] = 'tickets'
  );


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Ticket attachments
--    attachments already carried owner_type='ticket' in its comment, but only
--    staff could ever read or write a row. A client needs both, for their own
--    ticket only — that's the photo that makes a support request useful.
-- ════════════════════════════════════════════════════════════════════════════

create index if not exists idx_attachments_owner on attachments(owner_type, owner_id);

drop policy if exists p_att_client_ticket on attachments;
create policy p_att_client_ticket on attachments for select using (
  owner_type = 'ticket' and exists (
    select 1 from tickets t
     where t.id = attachments.owner_id
       and t.raised_by = auth.uid()));

drop policy if exists p_att_client_ticket_new on attachments;
create policy p_att_client_ticket_new on attachments for insert with check (
  owner_type = 'ticket'
  and uploaded_by = auth.uid()
  and exists (
    select 1 from tickets t
     where t.id = attachments.owner_id
       and t.raised_by = auth.uid()));

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0012_template_checklists.sql
-- ═══════════════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0013_stock_movement.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0013_stock_movement.sql — receiving a PO actually moves stock
--
-- Nothing ever wrote to stock_items after the seed, so the Store inventory and
-- its low-stock alerts were frozen: a received purchase order closed its
-- requirements and wrote a GRN, but the quantities never landed in stock.
--
-- The client-side markReceived() also could not fix this on its own —
-- stock_items is writable only by {admin,store} (0009), while receiving is done
-- by procurement — and it did four separate writes with no transaction. This
-- moves the whole operation into one security-definer RPC: atomic, permission
-- checked once, and able to touch stock_items.

create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  select status into v_status from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;

  -- Mark the PO received and fully receive every line.
  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Add the received quantities to stock, one row per catalog item. A PO can
  -- list the same item on more than one line, so sum first. Update the existing
  -- stock row if there is one; otherwise open one, carrying the item's unit.
  for r in
    select item_catalog_id, sum(qty)::numeric as q
      from po_lines where po_id = p_po
     group by item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  -- Goods receipt note + close the requirements this PO was raised against.
  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0014_client_ticket_visibility.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0014_client_ticket_visibility.sql — a client sees every ticket about their truck
--
-- The client could only see tickets where raised_by = themselves
-- (p_tickets_client, 0002). But Service raises tickets on a client's behalf
-- after a phone call or a site visit (fn_create_ticket stamps raised_by with the
-- service member), and those were invisible to the client — they could neither
-- follow the status nor reopen one. A client should see anything raised against
-- a truck that belongs to their account, whoever logged it.
--
-- Additive: RLS SELECT policies are OR'd, so this widens visibility without
-- touching the existing "own tickets" policy. Write access is unchanged — a
-- client still only inserts tickets as themselves (p_tickets_client_new).

drop policy if exists p_tickets_client_project on tickets;
create policy p_tickets_client_project on tickets for select using (
  exists (
    select 1 from projects p
     where p.id = tickets.project_id
       and p.client_account_id = public.my_client_account()
  )
);

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0015_rebaseline_on_delivery_change.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0015_rebaseline_on_delivery_change.sql
--
-- Changing the delivery date re-ran backward scheduling and moved every stage's
-- PLANNED dates, but left the ASSIGNED dates (what the PM committed to in Assign
-- work, shown as "Due …" on the stage) untouched. So after moving delivery
-- earlier, stages could still say they were "Due" *after* the new delivery date
-- — nonsensical, and confusing in testing.
--
-- Fix: a delivery-date change is a full re-plan. fn_recompute_schedule gets an
-- optional p_rebaseline_assigned flag; when true it also snaps each stage's
-- assigned_start/assigned_due to the freshly recomputed planned dates.
--
-- The flag defaults to FALSE so the other callers are unchanged: onboarding and
-- "add/edit material" recompute the plan and order-by dates WITHOUT wiping the
-- PM's per-stage commitments. Only the delivery-date action (setDeliveryDate)
-- passes true. Completed stages (status = 'done') are left alone — their dates
-- are history, not a plan.
--
-- The old 1-arg function is dropped and replaced with a single 2-arg version
-- (new arg defaulted), so every existing call site — the in-SQL
-- `perform public.fn_recompute_schedule(p_project)` calls and the app's 1-arg
-- rpc calls — keeps working and simply gets the default (no rebaseline).

drop function if exists public.fn_recompute_schedule(uuid);

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
  -- walk stages from last to first, laying out planned dates in reverse
  for r in
    select s.id, coalesce(ts.default_duration_days, 1) as dur
    from stages s
    left join template_stages ts on ts.id = s.template_stage_id
    where s.project_id = p_project
    order by s.ord desc
  loop
    v_dur := greatest(r.dur, 1);
    update stages
       set planned_end   = v_cursor,
           planned_start = v_cursor - (v_dur - 1)
     where id = r.id;
    v_cursor := (v_cursor - v_dur);  -- day before this stage starts
  end loop;

  -- order-by date for each requirement = needed_by - lead - buffer
  update procurement_requirements pr
     set order_by_date = pr.needed_by_date - ic.lead_time_days - ic.buffer_days
    from item_catalog ic
   where pr.item_catalog_id = ic.id
     and pr.project_id = p_project
     and pr.needed_by_date is not null;

  -- Full re-plan (delivery date changed): snap the PM's committed dates to the
  -- new plan so a stage is never "Due" after delivery. Completed stages keep
  -- their historical dates.
  if p_rebaseline_assigned then
    update stages
       set assigned_start = planned_start,
           assigned_due   = planned_end
     where project_id = p_project
       and status <> 'done';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0016_receive_requires_dispatch.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0016_receive_requires_dispatch.sql
--
-- A purchase order could be received straight from 'ordered', skipping
-- 'dispatched' — the Receive tab offered "Receive & verify" on ordered POs and
-- fn_receive_po (0013) never checked the current status. That breaks the
-- process: you can't receive goods a vendor hasn't shipped.
--
-- fn_receive_po now refuses unless the PO is 'dispatched' (or 'partial', a
-- part-shipment that can still be completed). Everything else is unchanged.
-- The server is the authority here; the UI is updated to match, but this guard
-- holds even if a client calls the RPC directly.

create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  select status into v_status from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;
  if v_status not in ('dispatched', 'partial') then
    raise exception 'Mark the purchase order dispatched before receiving it.';
  end if;

  -- Mark the PO received and fully receive every line.
  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Add the received quantities to stock, one row per catalog item. A PO can
  -- list the same item on more than one line, so sum first. Update the existing
  -- stock row if there is one; otherwise open one, carrying the item's unit.
  for r in
    select item_catalog_id, sum(qty)::numeric as q
      from po_lines where po_id = p_po
     group by item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  -- Goods receipt note + close the requirements this PO was raised against.
  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0017_stock_requests.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0017_stock_requests.sql
--
-- Store → Procurement essentials reorder loop.
--
-- Procurement doesn't only buy project materials (which the PM raises as
-- procurement_requirements, backward-scheduled against a delivery date). There
-- are general essentials — wheels, sheets, metal — that every trailer/kiosk
-- build consumes and that we keep in stock regardless of any one project.
--
-- Store watches inventory. When an essential runs low, Store raises a reorder
-- request straight to Procurement (mirroring how the PM raises project
-- requirements). Procurement sees it in "To Order" and cuts a general PO
-- (project_id null). On receipt fn_receive_po already tops up stock_items, and
-- now also closes the request.
--
-- This is manual on purpose: Store decides what and how much to reorder — no
-- automatic low-stock ordering, which tends to buy the wrong things.
--
-- Reuses the existing req_status enum ('pending','ordered','received').

create table if not exists public.stock_requests (
  id              uuid primary key default gen_random_uuid(),
  item_catalog_id uuid not null references item_catalog(id),
  qty             int  not null default 1 check (qty > 0),
  note            text,
  status          req_status not null default 'pending',
  requested_by    uuid references profiles(id),
  po_id           uuid references purchase_orders(id),
  created_at      timestamptz not null default now()
);

create index if not exists stock_requests_status_idx on public.stock_requests (status);
create index if not exists stock_requests_po_idx     on public.stock_requests (po_id);

alter table public.stock_requests enable row level security;

-- Read: any staff member (procurement acts on them, store/pm/admin see status).
drop policy if exists stock_requests_read on public.stock_requests;
create policy stock_requests_read on public.stock_requests
  for select using (public.has_role(array['admin','procurement','store','pm']));

-- Insert: store (or admin) raises the request. fn_request_stock is the intended
-- path, but this keeps a direct insert honest too.
drop policy if exists stock_requests_insert on public.stock_requests;
create policy stock_requests_insert on public.stock_requests
  for insert with check (public.has_role(array['admin','store']));

-- Update: procurement (or admin) links a PO / advances status.
drop policy if exists stock_requests_update on public.stock_requests;
create policy stock_requests_update on public.stock_requests
  for update using (public.has_role(array['admin','procurement']))
  with check (public.has_role(array['admin','procurement']));


-- Store raises a reorder request and Procurement is notified — the same shape
-- as the PM → assignee notifications elsewhere in the app.
create or replace function public.fn_request_stock(
  p_item uuid, p_qty int, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text;
begin
  if not public.has_role(array['admin','store']) then
    raise exception 'Only store or admin can request stock.' using errcode = '42501';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity must be greater than zero.';
  end if;

  select name into v_name from item_catalog where id = p_item;
  if not found then raise exception 'Item not found.'; end if;

  insert into stock_requests (item_catalog_id, qty, note, requested_by)
  values (p_item, p_qty, nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_id;

  perform public.fn_notify_role(
    array['procurement','admin'], 'stock_request',
    'Stock reorder requested',
    format('%s x %s needed', p_qty, v_name),
    'stock_request', v_id, auth.uid());

  perform public.fn_audit('request_stock', 'stock_request', v_id);
  return v_id;
end $$;


-- Re-create fn_receive_po (from 0016) so that receiving a PO also closes any
-- stock reorder requests it was raised against — the same way it already closes
-- procurement_requirements. Body is otherwise identical to 0016.
create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  select status into v_status from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;
  if v_status not in ('dispatched', 'partial') then
    raise exception 'Mark the purchase order dispatched before receiving it.';
  end if;

  -- Mark the PO received and fully receive every line.
  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Add the received quantities to stock, one row per catalog item. A PO can
  -- list the same item on more than one line, so sum first. Update the existing
  -- stock row if there is one; otherwise open one, carrying the item's unit.
  for r in
    select item_catalog_id, sum(qty)::numeric as q
      from po_lines where po_id = p_po
     group by item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  -- Goods receipt note + close the requirements this PO was raised against.
  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;
  update stock_requests          set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0018_intake_serialized.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0018_intake_serialized.sql
--
-- Intake, serialized-aware. Phase 2 of the inventory-truthfulness work.
--
-- Two kinds of item live in the catalog (item_catalog.serialized):
--   • Bulk / consumable (serialized = false) — screws, sheet, wire. On-hand is
--     a running quantity in stock_items.
--   • Serialized (serialized = true) — LED screens, inverters. Every physical
--     unit is a component_instance with its own serial; on-hand is how many are
--     'in_stock' (see StoreRepo.stock, Phase 1).
--
-- Until now fn_receive_po bumped stock_items for EVERY received line. For a
-- serialized item that double-counts: receive adds to stock_items AND Store
-- logs each unit as a component. So from here fn_receive_po only tops up
-- stock_items for bulk items; serialized items enter stock when Store logs
-- their serials (scanned off the vendor label at intake). The goods receipt and
-- requirement/stock-request closing behave exactly as before, for both kinds.
--
-- Body is otherwise identical to 0017's fn_receive_po (dispatch guard, GRN,
-- close procurement_requirements + stock_requests).

create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  select status into v_status from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;
  if v_status not in ('dispatched', 'partial') then
    raise exception 'Mark the purchase order dispatched before receiving it.';
  end if;

  -- Mark the PO received and fully receive every line.
  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Add received quantities to stock — BULK items only. Serialized items are
  -- counted from the component ledger, so topping up stock_items here would
  -- double-count them. A PO can list the same item on more than one line, so
  -- sum first; update the existing stock row or open one, carrying the unit.
  for r in
    select pl.item_catalog_id, sum(pl.qty)::numeric as q
      from po_lines pl
      join item_catalog ic on ic.id = pl.item_catalog_id
     where pl.po_id = p_po and ic.serialized = false
     group by pl.item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  -- Goods receipt note + close the requirements this PO was raised against.
  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;
  update stock_requests          set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0019_essential_items.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0019_essential_items.sql
--
-- Separate "who orders this item" from "how it is tracked".
--
-- Two independent facts about a catalogue item:
--   • serialized  — HOW it is tracked (per-unit component vs bulk quantity).
--   • is_essential — WHO orders it:
--       - Project-specific items (LED screen, a truck's BOM parts) come from the
--         PM: they land as procurement_requirements and procurement orders them.
--         These are NOT essentials.
--       - Essentials (sheets, metal, wheels) are general stock the Store keeps
--         regardless of any one project. When they run low the Store raises a
--         reorder request to procurement.
--
-- The Store's "Request from procurement" picker should only offer essentials —
-- a project part like an LED screen has no business being reordered by Store.
--
-- Bootstrap: existing bulk (non-serialized) items are, in practice, the general
-- essentials, so seed them as essential. Serialized items default to false
-- (project parts until someone says otherwise).

alter table public.item_catalog
  add column if not exists is_essential boolean not null default false;

update public.item_catalog set is_essential = true where serialized = false;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0020_po_approvals.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0020_po_approvals.sql
--
-- Multi-level Purchase Order approval + delay tracking, and the data an
-- office-level PO document needs (rates, tax, HSN, buyer/vendor identity).
--
-- The real-world flow the business runs:
--
--   Procurement raises the PO (with clarity from the PM)
--        └─► PM signs it            (level 1 — only for project POs)
--              └─► Final approver signs  (level 2 — a company owner/admin)
--                    └─► order is actually placed  →  ordered → dispatched → received
--
-- General / stock POs (wheels, sheets, metal — no project, no PM) skip the PM
-- step and go straight to the final approver.
--
-- Until now a PO was a bare INSERT that went live as 'ordered' the instant
-- Procurement created it — nobody signed anything, and there was no record of
-- who held it up when an order slipped because a signature was late. This
-- migration adds:
--   • a separate APPROVAL lifecycle (pending_pm → pending_final → approved /
--     rejected) that gates the existing FULFILMENT lifecycle (ordered →
--     dispatched → received). A PO cannot be dispatched or received until it is
--     approved (enforced by a trigger, not just the UI).
--   • po_approval_events — an immutable, timestamped trail of every signature /
--     rejection, so "the order was late because Puneet was travelling" is a
--     fact on the record, not a guess. This is the delay log for approvals.
--   • money + tax + HSN on the lines, buyer identity (company_settings) and
--     vendor GSTIN/address, so a proper PO document can be generated (0020 only
--     captures the data; the PDF is rendered in the app).
--
-- Reuses the existing po_status / req_status enums untouched.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. APPROVAL STATUS ENUM
-- ════════════════════════════════════════════════════════════════════════════
do $$ begin
  if not exists (select 1 from pg_type where typname = 'po_approval_status') then
    create type po_approval_status as enum ('pending_pm','pending_final','approved','rejected');
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. SCHEMA — approval fields + money + document identity
-- ════════════════════════════════════════════════════════════════════════════

-- Buyer identity for the top of a PO document (single row).
create table if not exists public.company_settings (
  id         uuid primary key default gen_random_uuid(),
  only_one   boolean not null default true unique,   -- enforces a single row
  name       text not null default 'Azimuth Business on Wheels',
  address    text,
  gstin      text,
  state      text,
  phone      text,
  email      text,
  logo_url   text,
  updated_at timestamptz not null default now()
);
insert into public.company_settings (only_one) values (true) on conflict (only_one) do nothing;

-- Vendor (supplier) identity for the PO document.
alter table public.vendors add column if not exists gstin   text;
alter table public.vendors add column if not exists address text;
alter table public.vendors add column if not exists state   text;
alter table public.vendors add column if not exists email   text;

-- Catalog: HSN/SAC code + an optional default rate to pre-fill a new PO line.
alter table public.item_catalog add column if not exists hsn_code     text;
alter table public.item_catalog add column if not exists default_rate numeric;

-- Line-level money: rate, GST %, HSN + a free-text description override.
alter table public.po_lines add column if not exists unit_price  numeric not null default 0;
alter table public.po_lines add column if not exists tax_rate    numeric not null default 0;  -- GST %
alter table public.po_lines add column if not exists hsn_code    text;
alter table public.po_lines add column if not exists description text;

-- Purchase order: approval lifecycle + the signatures + totals + doc fields.
alter table public.purchase_orders add column if not exists approval_status po_approval_status not null default 'pending_pm';
alter table public.purchase_orders add column if not exists subtotal        numeric not null default 0;
alter table public.purchase_orders add column if not exists tax_total       numeric not null default 0;
alter table public.purchase_orders add column if not exists amount          numeric not null default 0;  -- grand total
alter table public.purchase_orders add column if not exists needed_by       date;                        -- order-by deadline (for delay flagging)
alter table public.purchase_orders add column if not exists delivery_date   date;                        -- promised delivery on the document
alter table public.purchase_orders add column if not exists ship_to         text;
alter table public.purchase_orders add column if not exists payment_terms   text;
alter table public.purchase_orders add column if not exists notes           text;
alter table public.purchase_orders add column if not exists pm_id           uuid references profiles(id);
alter table public.purchase_orders add column if not exists submitted_by    uuid references profiles(id);
alter table public.purchase_orders add column if not exists submitted_at    timestamptz;
alter table public.purchase_orders add column if not exists pm_signed_by    uuid references profiles(id);
alter table public.purchase_orders add column if not exists pm_signed_at    timestamptz;
alter table public.purchase_orders add column if not exists final_signed_by uuid references profiles(id);
alter table public.purchase_orders add column if not exists final_signed_at timestamptz;
alter table public.purchase_orders add column if not exists rejected_by     uuid references profiles(id);
alter table public.purchase_orders add column if not exists rejected_at     timestamptz;
alter table public.purchase_orders add column if not exists rejection_reason text;

create index if not exists idx_po_approval on public.purchase_orders (approval_status);
create index if not exists idx_po_pm       on public.purchase_orders (pm_id);

-- Immutable trail of every approval event (the delay log for approvals).
create table if not exists public.po_approval_events (
  id          uuid primary key default gen_random_uuid(),
  po_id       uuid not null references purchase_orders(id) on delete cascade,
  event       text not null,                       -- created | pm_signed | final_signed | rejected
  from_status po_approval_status,
  to_status   po_approval_status,
  actor_id    uuid references profiles(id),
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists po_appr_events_po_idx on public.po_approval_events (po_id, created_at);

-- Sequential, human-friendly PO numbers (PO-00001…) generated server-side, the
-- same way tickets get T-001. The old client-side 'PO-<millis>' scheme could
-- collide and carried no ordering. The distinct zero-padded format won't clash
-- with any pre-existing 'PO-<millis>' rows.
create sequence if not exists public.po_number_seq;

-- Existing POs were already placed with the vendor, so they are effectively
-- approved — grandfather them in. Guarded on submitted_at (which every PO
-- raised through fn_create_po sets) so this is safe to re-run and never
-- auto-approves a genuinely pending PO.
update public.purchase_orders
   set approval_status = 'approved'
 where approval_status = 'pending_pm'
   and submitted_at is null;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. GUARD — a PO cannot be dispatched or received until it is approved
--    (defence in depth: the UI hides the action, this makes it impossible)
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.trg_po_require_approval() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status
     and new.status in ('dispatched','partial','received')
     and new.approval_status <> 'approved' then
    raise exception 'This purchase order must be fully approved before it can be dispatched or received.'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_po_require_approval on public.purchase_orders;
create trigger trg_po_require_approval
  before update on public.purchase_orders
  for each row execute function public.trg_po_require_approval();


-- ════════════════════════════════════════════════════════════════════════════
-- 4. FUNCTIONS
-- ════════════════════════════════════════════════════════════════════════════

-- Raise a PO. Procurement (or admin) only. Computes totals from the lines,
-- routes it to the PM (project PO) or straight to final approval (general PO),
-- optionally links + parks the requirement / stock request it fulfils, and
-- notifies the next signer.
--
-- p_lines is a jsonb array of:
--   { "item_catalog_id": uuid, "qty": int, "unit_price": numeric,
--     "tax_rate": numeric, "hsn_code": text, "description": text }
create or replace function public.fn_create_po(
  p_vendor        uuid    default null,
  p_project       uuid    default null,
  p_order_date    date    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default '[]'::jsonb,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null,
  p_requirement   uuid    default null,
  p_stock_request uuid    default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_po       uuid;
  v_num      text;
  v_pm       uuid;
  v_appr     po_approval_status;
  v_needed   date;
  v_subtotal numeric := 0;
  v_tax      numeric := 0;
  v_line     jsonb;
  v_qty      int;
  v_price    numeric;
  v_rate     numeric;
  v_lt       numeric;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can raise a purchase order.' using errcode = '42501';
  end if;

  -- Route: a project PO needs the PM's signature first; a general PO does not.
  if p_project is not null then
    select pm_id into v_pm from projects where id = p_project;
  end if;
  v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Carry the order-by deadline through for delay flagging.
  if p_requirement is not null then
    select order_by_date into v_needed from procurement_requirements where id = p_requirement;
  end if;

  -- Sum the lines up front for the header totals.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_qty   := coalesce((v_line->>'qty')::int, 1);
    v_price := coalesce((v_line->>'unit_price')::numeric, 0);
    v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
    v_lt    := v_qty * v_price;
    v_subtotal := v_subtotal + v_lt;
    v_tax      := v_tax + (v_lt * v_rate / 100.0);
  end loop;

  v_num := 'PO-' || to_char(nextval('public.po_number_seq'), 'FM00000');

  insert into purchase_orders (
    po_number, vendor_id, project_id, status, approval_status,
    order_date, delivery_date, needed_by, ship_to, payment_terms, notes,
    subtotal, tax_total, amount, pm_id, submitted_by, submitted_at, created_by)
  values (
    v_num, p_vendor, p_project, 'ordered', v_appr,
    coalesce(p_order_date, current_date), p_delivery_date, v_needed,
    nullif(btrim(coalesce(p_ship_to, '')), ''),
    nullif(btrim(coalesce(p_payment_terms, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''),
    v_subtotal, v_tax, v_subtotal + v_tax, v_pm, auth.uid(), now(), auth.uid())
  returning id into v_po;

  -- Lines.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
    values (
      v_po,
      (v_line->>'item_catalog_id')::uuid,
      coalesce((v_line->>'qty')::int, 1),
      coalesce((v_line->>'unit_price')::numeric, 0),
      coalesce((v_line->>'tax_rate')::numeric, 0),
      nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
      nullif(btrim(coalesce(v_line->>'description', '')), ''));
  end loop;

  -- Park the demand this PO fulfils so it leaves the To-Order list. If the PO
  -- is later rejected, fn_reject_po puts it back.
  if p_requirement is not null then
    update procurement_requirements set status = 'ordered', po_id = v_po where id = p_requirement;
  end if;
  if p_stock_request is not null then
    update stock_requests set status = 'ordered', po_id = v_po where id = p_stock_request;
  end if;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (v_po, 'created', null, v_appr, auth.uid());

  -- Notify the next signer.
  if v_appr = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' needs your signature',
      'Procurement raised a purchase order on your build — review and sign it.',
      'purchase_order', v_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' needs final approval',
      'A purchase order is awaiting final sign-off.',
      'purchase_order', v_po, auth.uid());
  end if;

  perform public.fn_audit('create_po', 'purchase_order', v_po);
  return v_po;
end $$;


-- PM signs a project PO (level 1). Moves it to the final approver.
create or replace function public.fn_pm_sign_po(p_po uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_appr po_approval_status; v_num text;
begin
  select pm_id, approval_status, po_number into v_pm, v_appr, v_num
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only the build''s project manager (or an admin) can sign this purchase order.'
      using errcode = '42501';
  end if;
  if v_appr <> 'pending_pm' then
    raise exception 'This purchase order is not awaiting a project manager''s signature.';
  end if;

  update purchase_orders
     set approval_status = 'pending_final', pm_signed_by = auth.uid(), pm_signed_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id, note)
  values (p_po, 'pm_signed', 'pending_pm', 'pending_final', auth.uid(),
          nullif(btrim(coalesce(p_note, '')), ''));

  perform public.fn_notify_role(array['admin'], 'po_approval',
    v_num || ' needs final approval',
    'Signed by the project manager — awaiting final sign-off.',
    'purchase_order', p_po, auth.uid());

  perform public.fn_audit('pm_sign_po', 'purchase_order', p_po);
end $$;


-- Final approver (admin / owner) signs off (level 2). The order is now placed.
create or replace function public.fn_final_approve_po(p_po uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_appr po_approval_status; v_num text; v_sub uuid; v_pm uuid;
begin
  select approval_status, po_number, submitted_by, pm_id into v_appr, v_num, v_sub, v_pm
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;

  if not public.is_admin() then
    raise exception 'Only a company owner / admin can give final approval.' using errcode = '42501';
  end if;
  if v_appr <> 'pending_final' then
    raise exception 'This purchase order is not awaiting final approval.';
  end if;

  update purchase_orders
     set approval_status = 'approved', final_signed_by = auth.uid(), final_signed_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id, note)
  values (p_po, 'final_signed', 'pending_final', 'approved', auth.uid(),
          nullif(btrim(coalesce(p_note, '')), ''));

  -- Tell whoever raised it (and the PM) that the order is live.
  perform public.fn_notify(v_sub, 'po_approved',
    v_num || ' approved',
    'Final approval is in — you can place the order with the vendor.',
    'purchase_order', p_po);
  if v_pm is not null and v_pm <> coalesce(v_sub, '00000000-0000-0000-0000-000000000000') then
    perform public.fn_notify(v_pm, 'po_approved',
      v_num || ' approved', 'The purchase order on your build has been approved.',
      'purchase_order', p_po);
  end if;

  perform public.fn_audit('approve_po', 'purchase_order', p_po);
end $$;


-- Reject at either step, with a mandatory reason. This is a rework loop, not a
-- dead end: the PO goes back to whoever raised it (with the remark) so they can
-- fix and resubmit it (fn_resubmit_po). The requirement it fulfils stays parked
-- against it — the PO is being reworked, not abandoned.
--   • Whoever rejects, procurement (the raiser) is put on the hook to fix it.
--   • When the *admin* rejects, the PM is also told — they had signed it, and
--     their signature is undone (a resubmit will come back to them).
create or replace function public.fn_reject_po(p_po uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_appr po_approval_status; v_num text; v_sub uuid; v_admin_rejected boolean;
begin
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to reject a purchase order.';
  end if;

  select pm_id, approval_status, po_number, submitted_by into v_pm, v_appr, v_num, v_sub
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;

  if v_appr not in ('pending_pm','pending_final') then
    raise exception 'Only a purchase order still awaiting approval can be rejected.';
  end if;
  -- Admin can reject at any step; the PM only their own build's PM step.
  if not (public.is_admin() or (v_appr = 'pending_pm' and v_pm = auth.uid())) then
    raise exception 'You are not allowed to reject this purchase order.' using errcode = '42501';
  end if;

  v_admin_rejected := (v_appr = 'pending_final');   -- only the admin can reject at that step

  update purchase_orders
     set approval_status = 'rejected', rejected_by = auth.uid(), rejected_at = now(),
         rejection_reason = btrim(p_reason)
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id, note)
  values (p_po, 'rejected', v_appr, 'rejected', auth.uid(), btrim(p_reason));

  -- Back to procurement to fix and resubmit.
  perform public.fn_notify(v_sub, 'po_rejected',
    v_num || ' was sent back',
    'Reason: ' || btrim(p_reason) || ' — fix it and resubmit.', 'purchase_order', p_po);

  -- The admin overruled a PO the PM had already signed → keep the PM in the loop.
  if v_admin_rejected and v_pm is not null
     and v_pm <> coalesce(v_sub, '00000000-0000-0000-0000-000000000000') then
    perform public.fn_notify(v_pm, 'po_rejected',
      v_num || ' was rejected by the owner',
      'The purchase order you signed on your build was rejected. Reason: ' || btrim(p_reason),
      'purchase_order', p_po);
  end if;

  perform public.fn_audit('reject_po', 'purchase_order', p_po);
end $$;


-- Fix a rejected PO and send it round again. Procurement (or admin) only, and
-- only while it is rejected. If new lines are supplied they replace the old ones
-- and the totals are recomputed; vendor / delivery / terms are updated too. The
-- signatures are wiped and it re-enters the chain from the top — a project PO
-- goes back to its PM, a general PO straight to final approval — so a changed
-- price or vendor is re-verified, not waved through on the old signature.
create or replace function public.fn_resubmit_po(
  p_po            uuid,
  p_vendor        uuid    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default null,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_appr po_approval_status; v_sub uuid; v_project uuid; v_pm uuid; v_num text; v_next po_approval_status;
  v_subtotal numeric := 0; v_tax numeric := 0; v_line jsonb; v_qty int; v_price numeric; v_rate numeric; v_lt numeric;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can resubmit a purchase order.' using errcode = '42501';
  end if;

  select approval_status, submitted_by, project_id, po_number into v_appr, v_sub, v_project, v_num
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_appr <> 'rejected' then
    raise exception 'Only a rejected purchase order can be resubmitted.';
  end if;

  if v_project is not null then
    select pm_id into v_pm from projects where id = v_project;
  end if;
  v_next := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Replace the lines + recompute totals when a new set is supplied.
  if p_lines is not null then
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_qty   := coalesce((v_line->>'qty')::int, 1);
      v_price := coalesce((v_line->>'unit_price')::numeric, 0);
      v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
      v_lt    := v_qty * v_price;
      v_subtotal := v_subtotal + v_lt;
      v_tax      := v_tax + (v_lt * v_rate / 100.0);
    end loop;

    delete from po_lines where po_id = p_po;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
      values (
        p_po,
        (v_line->>'item_catalog_id')::uuid,
        coalesce((v_line->>'qty')::int, 1),
        coalesce((v_line->>'unit_price')::numeric, 0),
        coalesce((v_line->>'tax_rate')::numeric, 0),
        nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
        nullif(btrim(coalesce(v_line->>'description', '')), ''));
    end loop;

    update purchase_orders
       set vendor_id     = coalesce(p_vendor, vendor_id),
           delivery_date = coalesce(p_delivery_date, delivery_date),
           payment_terms = nullif(btrim(coalesce(p_payment_terms, '')), ''),
           notes         = nullif(btrim(coalesce(p_notes, '')), ''),
           ship_to       = nullif(btrim(coalesce(p_ship_to, '')), ''),
           subtotal = v_subtotal, tax_total = v_tax, amount = v_subtotal + v_tax
     where id = p_po;
  end if;

  -- Wipe the signatures and re-enter the chain from the top.
  update purchase_orders
     set approval_status = v_next, pm_id = v_pm,
         pm_signed_by = null, pm_signed_at = null,
         final_signed_by = null, final_signed_at = null,
         rejected_by = null, rejected_at = null, rejection_reason = null,
         submitted_by = auth.uid(), submitted_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (p_po, 'resubmitted', 'rejected', v_next, auth.uid());

  if v_next = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' was revised — please sign',
      'Procurement addressed the feedback and resubmitted this purchase order.',
      'purchase_order', p_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' was revised — needs approval',
      'A rejected purchase order has been revised and resubmitted.',
      'purchase_order', p_po, auth.uid());
  end if;

  perform public.fn_audit('resubmit_po', 'purchase_order', p_po);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. VIEW — the approvals queue, with how long each PO has been waiting
--    security_invoker so the reader's RLS on purchase_orders applies.
-- ════════════════════════════════════════════════════════════════════════════
drop view if exists public.v_po_pending_approvals;
create view public.v_po_pending_approvals with (security_invoker = on) as
  select
    po.id, po.po_number, po.approval_status, po.amount,
    po.project_id, po.pm_id, po.vendor_id, po.needed_by,
    v.name  as vendor_name,
    pr.code as project_code,
    po.submitted_at, po.submitted_by, po.pm_signed_at,
    case when po.approval_status = 'pending_pm'    then po.submitted_at
         when po.approval_status = 'pending_final' then po.pm_signed_at end as waiting_since,
    round(extract(epoch from (now() -
      case when po.approval_status = 'pending_pm'    then po.submitted_at
           when po.approval_status = 'pending_final' then po.pm_signed_at end)) / 3600.0, 1) as waiting_hours,
    (po.needed_by is not null and po.needed_by < current_date) as overdue
  from purchase_orders po
  left join vendors  v  on v.id  = po.vendor_id
  left join projects pr on pr.id = po.project_id
  where po.approval_status in ('pending_pm','pending_final')
  order by waiting_since asc nulls last;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. RLS
-- ════════════════════════════════════════════════════════════════════════════

-- New tables aren't covered by the 0002 enable-RLS loop — turn it on here.
alter table public.company_settings   enable row level security;
alter table public.po_approval_events enable row level security;

-- Company settings: any staff can read (a PO shows the buyer block); admin edits.
drop policy if exists company_settings_read  on public.company_settings;
drop policy if exists company_settings_write on public.company_settings;
create policy company_settings_read  on public.company_settings for select using (public.is_staff());
create policy company_settings_write on public.company_settings for all
  using (public.is_admin()) with check (public.is_admin());

-- Approval events: readable by the roles that touch procurement; written only by
-- the SECURITY DEFINER functions above (no direct write policy).
drop policy if exists po_appr_events_read on public.po_approval_events;
create policy po_appr_events_read on public.po_approval_events for select
  using (public.has_role(array['admin','pm','procurement','store']));

-- Tighten purchase_orders: costs are now on the record, so keep them off the
-- shop floor (workshop / design / service / client). Read = the roles that need
-- it; writes still {admin,procurement}. Crucially, DROP the blanket insert path
-- — a PO must now be raised through fn_create_po so it enters the approval flow
-- instead of going live unsigned.
drop policy if exists purchase_orders_read   on public.purchase_orders;
drop policy if exists purchase_orders_write  on public.purchase_orders;
drop policy if exists purchase_orders_update on public.purchase_orders;
create policy purchase_orders_read on public.purchase_orders for select
  using (public.has_role(array['admin','pm','procurement','store']));
create policy purchase_orders_update on public.purchase_orders for update
  using (public.has_role(array['admin','procurement']))
  with check (public.has_role(array['admin','procurement']));

-- po_lines carry rates now — same read scope as the header.
drop policy if exists po_lines_read  on public.po_lines;
drop policy if exists po_lines_staff on public.po_lines;
create policy po_lines_read on public.po_lines for select
  using (public.has_role(array['admin','pm','procurement','store']));
-- po_lines_write ({admin,procurement}) from 0009 stays as-is.

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0021_ops_command_center.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0021_ops_command_center.sql
--
-- The operations backbone the owner asked for — so nobody has to walk the floor
-- asking "which build is where, who's on it, what needs signing first".
--
-- Three things:
--   1. SUB-TEAMS. A department (role) like Workshop is big and splits into teams
--      — Welding, Paint, Electrical, Fitter. Smaller departments (Design) have
--      none. So sub-teams are optional and belong to a department; a person has
--      a department (role) + an optional sub-team.
--   2. A FACTORY BOARD view (v_ops_board) — one row per active build: what stage
--      it's at, which department/sub-team + person is on it, how long it's sat
--      there, its status, and its next order-by date.
--   3. PO APPROVAL PRIORITY. Many POs land at once; the owner should sign the
--      one that unblocks the soonest delivery first. Priority is derived
--      deterministically from the item's order-by date, with an admin override.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. SUB-TEAMS (department → team)
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.sub_teams (
  id         uuid primary key default gen_random_uuid(),
  role       user_role not null,          -- the department this team sits under
  name       text not null,
  created_at timestamptz not null default now(),
  unique (role, name)
);

-- Workshop's teams to start with; other departments add their own as needed.
insert into public.sub_teams (role, name) values
  ('workshop', 'Welding'),
  ('workshop', 'Paint'),
  ('workshop', 'Electrical'),
  ('workshop', 'Fitter')
on conflict (role, name) do nothing;

-- A person's team within their department (optional — Design has none).
alter table public.profiles add column if not exists sub_team_id uuid references sub_teams(id);

alter table public.sub_teams enable row level security;
drop policy if exists sub_teams_read  on public.sub_teams;
drop policy if exists sub_teams_write on public.sub_teams;
create policy sub_teams_read  on public.sub_teams for select using (public.is_staff());
create policy sub_teams_write on public.sub_teams for all
  using (public.is_admin()) with check (public.is_admin());


-- ════════════════════════════════════════════════════════════════════════════
-- 2. PO APPROVAL PRIORITY
-- ════════════════════════════════════════════════════════════════════════════
alter table public.purchase_orders add column if not exists priority_override text
  check (priority_override in ('critical','high','medium','low'));

-- Admin can force a priority (or clear it to fall back to the auto rule).
create or replace function public.fn_set_po_priority(p_po uuid, p_priority text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can change a purchase order''s priority.' using errcode = '42501';
  end if;
  if p_priority is not null and p_priority not in ('critical','high','medium','low') then
    raise exception 'Invalid priority.';
  end if;
  update purchase_orders set priority_override = p_priority where id = p_po;
  perform public.fn_audit('set_po_priority', 'purchase_order', p_po);
end $$;

-- Rebuild the approvals queue with a deterministic priority + a sort rank.
-- Rule (override always wins):
--   overdue (needed_by in the past) → critical
--   needed within 3 days            → high
--   needed within 7 days            → medium
--   needed later                    → low
--   no order-by date (general PO)   → medium
drop view if exists public.v_po_pending_approvals;
create view public.v_po_pending_approvals with (security_invoker = on) as
  select b.*,
         case b.priority when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end as priority_rank
  from (
    select
      po.id, po.po_number, po.approval_status, po.amount,
      po.project_id, po.pm_id, po.vendor_id, po.needed_by, po.priority_override,
      v.name  as vendor_name,
      pr.code as project_code,
      po.submitted_at, po.submitted_by, po.pm_signed_at,
      case when po.approval_status = 'pending_pm'    then po.submitted_at
           when po.approval_status = 'pending_final' then po.pm_signed_at end as waiting_since,
      round(extract(epoch from (now() -
        case when po.approval_status = 'pending_pm'    then po.submitted_at
             when po.approval_status = 'pending_final' then po.pm_signed_at end)) / 3600.0, 1) as waiting_hours,
      (po.needed_by is not null and po.needed_by < current_date) as overdue,
      coalesce(po.priority_override,
        case
          when po.needed_by is null               then 'medium'
          when po.needed_by <  current_date        then 'critical'
          when po.needed_by <= current_date + 3     then 'high'
          when po.needed_by <= current_date + 7     then 'medium'
          else 'low'
        end) as priority
    from purchase_orders po
    left join vendors  v  on v.id  = po.vendor_id
    left join projects pr on pr.id = po.project_id
    where po.approval_status in ('pending_pm','pending_final')
  ) b
  order by priority_rank asc, b.needed_by asc nulls last, b.waiting_since asc nulls last;

grant select on public.v_po_pending_approvals to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. FACTORY BOARD — one row per active build, for the owner's command center
--    security_invoker so the reader's RLS applies (admin/staff see the fleet).
-- ════════════════════════════════════════════════════════════════════════════
drop view if exists public.v_ops_board;
create view public.v_ops_board with (security_invoker = on) as
  select
    p.id as project_id, p.code, p.name, p.status, p.progress_pct,
    p.pm_id, pm.full_name as pm_name,
    p.current_stage_id,
    s.name       as current_stage_name,
    s.discipline as current_discipline,
    s.status     as current_stage_status,
    s.actual_start as stage_started,
    s.planned_end  as stage_planned_end,
    s.assigned_due as stage_due,
    case when s.actual_start is not null then (current_date - s.actual_start) end as days_in_stage,
    a.id        as assignee_id,
    a.full_name as assignee_name,
    a.role      as assignee_role,
    st.id       as sub_team_id,
    st.name     as sub_team_name,
    (select min(rq.order_by_date) from procurement_requirements rq
       where rq.project_id = p.id and rq.status = 'pending') as next_order_by
  from projects p
  left join profiles  pm on pm.id = p.pm_id
  left join stages    s  on s.id  = p.current_stage_id
  left join profiles  a  on a.id  = s.assignee_id
  left join sub_teams st on st.id = a.sub_team_id
  where p.status <> 'delivered';

grant select on public.v_ops_board to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0022_project_delays.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0022_project_delays.sql
--
-- Delay attribution for the project dossier. delay_logs already records why a
-- stage slipped (reason, days, note, who logged it), but only per stage — there
-- was no way to see, for a whole build, WHERE it slipped and WHO held that
-- stage. This view joins each delay to its stage + the person logging it + the
-- stage's assignee, so the admin dossier can answer "which stage, who, why, how
-- many days" in one place.
--
-- No new tables — pure read model over existing data.

drop view if exists public.v_project_delays;
create view public.v_project_delays with (security_invoker = on) as
  select
    dl.id,
    s.project_id,
    s.id         as stage_id,
    s.name       as stage_name,
    s.discipline,
    dl.reason_code,
    dl.days_delayed,
    dl.note,
    dl.created_at,
    lg.full_name  as logged_by_name,
    asg.full_name as assignee_name
  from delay_logs dl
  join stages   s   on s.id  = dl.stage_id
  left join profiles lg  on lg.id  = dl.logged_by
  left join profiles asg on asg.id = s.assignee_id;

grant select on public.v_project_delays to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0023_truck_record.sql
-- ═══════════════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0024_status_delivery_date.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0024_status_delivery_date.sql
--
-- Bug fix: a build past its promised delivery date kept showing "on track".
--
-- fn_recompute_status only ever looked at per-stage planned_end dates — it never
-- checked the project's own target_delivery_date. So a build whose stages had no
-- planned_end (or a future one) but whose promised delivery date had already
-- passed stayed on_track. Now:
--   • not delivered AND target_delivery_date is in the past  → delayed
--   • not delivered AND delivery is within 7 days with work left → at_risk
-- (the old stage-overrun / order-by / unstarted-stage rules still apply).
--
-- Also re-runs the status of every build once, so existing data corrects itself
-- the moment this migration is applied (rather than waiting for the next edit).

create or replace function public.fn_recompute_status(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_delivered date; v_target date; v_late int; v_risk int; v_open int; v_status project_status;
begin
  select actual_delivery_date, target_delivery_date into v_delivered, v_target
    from projects where id = p_project;

  if v_delivered is not null then
    v_status := 'delivered';
  else
    -- a stage that isn't done has already blown past its planned end
    select count(*) into v_late from stages
     where project_id = p_project and status <> 'done'
       and planned_end is not null and planned_end < current_date;

    -- the promised delivery date has passed, or a stage overran → delayed
    if (v_target is not null and v_target < current_date) or v_late > 0 then
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

      -- or delivery is a week out (or less) and there's still work left
      if v_risk = 0 and v_target is not null and v_target <= current_date + 7 then
        select count(*) into v_open from stages
         where project_id = p_project and status <> 'done';
        if v_open > 0 then v_risk := 1; end if;
      end if;

      v_status := case when v_risk > 0 then 'at_risk'::project_status
                                       else 'on_track'::project_status end;
    end if;
  end if;

  update projects set status = v_status
   where id = p_project and status is distinct from v_status;
end $$;

-- Correct every existing build now (a build that was silently on_track past its
-- delivery date flips to delayed on deploy, not on the next stage edit).
select public.fn_refresh_all_statuses();

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0025_design_version_atomic.sql
-- ═══════════════════════════════════════════════════════════════════════
--
-- Atomic design-version numbering.
--
-- addVersion() in the app did read-max-then-insert: it read an artifact's
-- highest version_no and inserted max+1. But DESIGN IS A TEAM, not one person —
-- more than one designer can be on the same build. Two "new version"
-- submissions milliseconds apart both read the same max and both insert the
-- SAME version_no, then each overwrites current_version_id: a lost update.
-- Nothing stopped it because version_no had no uniqueness.
--
-- This makes version numbering safe:
--   * a UNIQUE index on (artifact_id, version_no) so a duplicate can never land
--   * fn_add_design_version() computes the next number under a row lock on the
--     artifact, inserts the version and repoints current_version_id — all in
--     one transaction, so concurrent callers serialise instead of racing.
--
-- Idempotent: safe to re-run.


-- 1. Uniqueness — a version number is unique within its artifact.
create unique index if not exists ux_design_versions_artifact_no
  on design_versions (artifact_id, version_no);


-- 2. Atomic "add a new version" (after a change request, or a redraft).
create or replace function public.fn_add_design_version(
  p_artifact    uuid,
  p_model_url   text default null,
  p_image_url   text default null,
  p_change_note text default null,
  p_submit      boolean default false)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_next int;
  v_id   uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can add a design version.' using errcode = '42501';
  end if;

  -- Lock the artifact row so concurrent version inserts for the SAME artifact
  -- serialise: a second caller waits here, then reads the number the first one
  -- just committed instead of colliding on it.
  perform 1 from design_artifacts where id = p_artifact for update;
  if not found then
    raise exception 'Design not found.';
  end if;

  select coalesce(max(version_no), 0) + 1 into v_next
    from design_versions where artifact_id = p_artifact;

  insert into design_versions (artifact_id, version_no, model_url, file_url, change_note)
    values (p_artifact, v_next, nullif(p_model_url, ''), nullif(p_image_url, ''), nullif(p_change_note, ''))
    returning id into v_id;

  update design_artifacts
     set current_version_id = v_id,
         status = (case when p_submit then 'pending_approval' else 'draft' end)::design_status,
         client_feedback = null
   where id = p_artifact;

  return v_id;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0026_demo_hardening.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0026_demo_hardening.sql
--
-- The audit pass before the demo found a set of real defects in the functions
-- the two hero features depend on, plus a handful of rules that were still only
-- enforced in the UI. This closes them in one migration. No schema additions
-- beyond one policy change and a FK sweep; everything here is idempotent and
-- safe to re-run.
--
--  1. fn_recompute_schedule — a delivery-date change left every material's
--     needed-by (and therefore its order-by alert) on the OLD plan, and never
--     refreshed the build's status. Hero #1 went stale the moment a PM pushed
--     a date.
--  2. fn_resubmit_po — wiped notes / ship-to / payment terms, and dropped a
--     vendor or delivery-date change entirely when the lines weren't resent.
--  3. fn_receive_po — read the PO status without a row lock, so two taps
--     doubled the stock and wrote two GRNs.
--  4. fn_reopen_ticket — had no caller check at all: any signed-in user could
--     reopen any ticket and force it to high priority.
--  5. trg_guard_stages — didn't guard status / actual_*, so an assignee could
--     mark their own stage done with a direct UPDATE, skipping submit+approve.
--  6. fn_notify* / fn_audit were callable by anyone over RPC (spoofed
--     notifications). Revoked from `authenticated`.
--  7. Store couldn't create a catalogue item, so its own "new item" sheets
--     failed on RLS.
--  8. An invited member could never become 'active' — the set-password screen's
--     own update was blocked by RLS.
--  9. Submitting a design told the client nothing; the "they've been notified"
--     banner was untrue. fn_create_design / fn_add_design_version now notify.
-- 10. Offboarding a member failed on the seven FKs added after 0009's sweep.
-- 11. A fresh / demo database had no essential items, so Store's "request from
--     procurement" picker was empty.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. BACKWARD SCHEDULING — a delivery-date change is a full re-plan (Hero #1)
--
-- procurement_requirements.needed_by_date was written once, at onboarding, from
-- the stage's planned_start at that moment. Nothing ever moved it again, and
-- order_by_date is derived FROM it — so after "Log delay + push the delivery
-- date" every material still alerted against the old schedule, v_order_due
-- showed a wrong "order in N days", and fn_recompute_status kept forcing the
-- build to at_risk off a stale order_by_date.
--
-- On a rebaseline (the delivery-date path) each still-pending requirement is
-- re-pointed at its own stage's new planned_start before order-by is recomputed.
-- Requirements that are already ordered or received are history and are left
-- alone, as are requirements with no stage to anchor to (added by hand by the
-- PM) — those keep whatever needed-by the PM set.
--
-- The function also ends by refreshing the project's status. planned_* changes
-- don't fire t_stage_progress (it's `after update of status`), so a build kept
-- showing 'delayed' after its date was pushed until some screen happened to
-- call fn_refresh_all_statuses.
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
  -- walk stages from last to first, laying out planned dates in reverse
  for r in
    select s.id, coalesce(ts.default_duration_days, 1) as dur
    from stages s
    left join template_stages ts on ts.id = s.template_stage_id
    where s.project_id = p_project
    order by s.ord desc
  loop
    v_dur := greatest(r.dur, 1);
    update stages
       set planned_end   = v_cursor,
           planned_start = v_cursor - (v_dur - 1)
     where id = r.id;
    v_cursor := (v_cursor - v_dur);  -- day before this stage starts
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
-- 2. fn_resubmit_po — stop losing the fields the caller didn't resend
--
-- Two defects:
--   • vendor_id / delivery_date used coalesce(arg, existing), but
--     payment_terms / notes / ship_to used nullif(btrim(coalesce(arg,''))',''),
--     so a null argument ERASED the stored value. The app's resubmit never
--     sends notes or ship-to, so both were nulled on every resubmit.
--   • The whole header UPDATE sat inside `if p_lines is not null`, so a
--     resubmit that changed only the vendor or the delivery date was silently
--     discarded.
--
-- Now: the header always updates, and every optional text field keeps its
-- current value when the argument is null. Passing an empty string still
-- clears a field deliberately.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_resubmit_po(
  p_po            uuid,
  p_vendor        uuid    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default null,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_appr po_approval_status; v_sub uuid; v_project uuid; v_pm uuid; v_num text; v_next po_approval_status;
  v_subtotal numeric := 0; v_tax numeric := 0; v_line jsonb; v_qty int; v_price numeric; v_rate numeric; v_lt numeric;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can resubmit a purchase order.' using errcode = '42501';
  end if;

  select approval_status, submitted_by, project_id, po_number into v_appr, v_sub, v_project, v_num
    from purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_appr <> 'rejected' then
    raise exception 'Only a rejected purchase order can be resubmitted.';
  end if;

  if v_project is not null then
    select pm_id into v_pm from projects where id = v_project;
  end if;
  v_next := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Replace the lines + recompute the totals only when a new set is supplied.
  if p_lines is not null then
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_qty   := coalesce((v_line->>'qty')::int, 1);
      v_price := coalesce((v_line->>'unit_price')::numeric, 0);
      v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
      v_lt    := v_qty * v_price;
      v_subtotal := v_subtotal + v_lt;
      v_tax      := v_tax + (v_lt * v_rate / 100.0);
    end loop;

    delete from po_lines where po_id = p_po;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
      values (
        p_po,
        (v_line->>'item_catalog_id')::uuid,
        coalesce((v_line->>'qty')::int, 1),
        coalesce((v_line->>'unit_price')::numeric, 0),
        coalesce((v_line->>'tax_rate')::numeric, 0),
        nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
        nullif(btrim(coalesce(v_line->>'description', '')), ''));
    end loop;

    update purchase_orders
       set subtotal = v_subtotal, tax_total = v_tax, amount = v_subtotal + v_tax
     where id = p_po;
  end if;

  -- Header + wipe the signatures and re-enter the chain from the top. Every
  -- optional field keeps its current value when the caller passes null.
  update purchase_orders
     set vendor_id       = coalesce(p_vendor, vendor_id),
         delivery_date   = coalesce(p_delivery_date, delivery_date),
         payment_terms   = case when p_payment_terms is null then payment_terms
                                else nullif(btrim(p_payment_terms), '') end,
         notes           = case when p_notes is null then notes
                                else nullif(btrim(p_notes), '') end,
         ship_to         = case when p_ship_to is null then ship_to
                                else nullif(btrim(p_ship_to), '') end,
         approval_status = v_next, pm_id = v_pm,
         pm_signed_by = null, pm_signed_at = null,
         final_signed_by = null, final_signed_at = null,
         rejected_by = null, rejected_at = null, rejection_reason = null,
         submitted_by = auth.uid(), submitted_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (p_po, 'resubmitted', 'rejected', v_next, auth.uid());

  if v_next = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' was revised — please sign',
      'Procurement addressed the feedback and resubmitted this purchase order.',
      'purchase_order', p_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' was revised — needs approval',
      'A rejected purchase order has been revised and resubmitted.',
      'purchase_order', p_po, auth.uid());
  end if;

  perform public.fn_audit('resubmit_po', 'purchase_order', p_po);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. fn_receive_po — lock the row before reading its status
--
-- Two people (or two taps) receiving the same PO both read status='dispatched',
-- both passed the guard, and both added the quantities: stock doubled and two
-- GRNs were written. `for update` makes the second caller wait and then see
-- 'received', so it raises instead. Body otherwise identical to 0018.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  -- Serialise concurrent receives of the same PO.
  select status into v_status from purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;
  if v_status not in ('dispatched', 'partial') then
    raise exception 'Mark the purchase order dispatched before receiving it.';
  end if;

  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Bulk items only: a serialized item enters stock when Store logs its serial,
  -- so topping up stock_items here would double-count it.
  for r in
    select pl.item_catalog_id, sum(pl.qty)::numeric as q
      from po_lines pl
      join item_catalog ic on ic.id = pl.item_catalog_id
     where pl.po_id = p_po and ic.serialized = false
     group by pl.item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;
  update stock_requests          set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. fn_reopen_ticket — who may reopen
--
-- It had no caller check whatsoever, and it forces priority to 'high' and
-- resets the SLA clock. Any signed-in user could jump any ticket to the front
-- of the service queue. Now: the client the ticket belongs to, the service
-- team, or an admin.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_reopen_ticket(p_ticket uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_status ticket_status; v_assignee uuid; v_reason text;
        v_raised uuid; v_ca uuid;
begin
  select t.ticket_number, t.status, t.assigned_to, t.raised_by, p.client_account_id
    into v_num, v_status, v_assignee, v_raised, v_ca
    from tickets t left join projects p on p.id = t.project_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;

  -- The client whose truck it is (or who raised it), service, or an admin.
  --
  -- coalesce, and not for tidiness: `v_ca = public.my_client_account()` is NULL
  -- for any staff member (they have no client account), so the whole OR came out
  -- NULL rather than false — and `if not NULL then` is *false*, so the guard did
  -- not fire and an unrelated welder could reopen anyone's ticket. Exactly the
  -- same trap as `is_admin()` in §14, which is why both are spelled out.
  if not coalesce(
       public.has_role(array['admin','service'])
    or v_raised = auth.uid()
    or (v_ca is not null and v_ca = public.my_client_account())
  , false) then
    raise exception 'Only the client this request belongs to, or the service team, can reopen it.'
      using errcode = '42501';
  end if;

  if v_status not in ('resolved', 'closed') then
    raise exception 'This ticket is still open.';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  update tickets
     set status = 'in_progress', resolved_at = null, closed_at = null,
         priority = 'high',                       -- a repeat visit jumps the queue
         sla_due = now() + (public.fn_sla_hours('high') || ' hours')::interval
   where id = p_ticket;

  perform public.fn_notify_role(array['service', 'admin'], 'ticket',
    v_num || ' reopened',
    coalesce(v_reason, 'The issue is not resolved.'), 'ticket', p_ticket, auth.uid());
  perform public.fn_notify(v_assignee, 'ticket', v_num || ' reopened',
    coalesce(v_reason, 'The issue is not resolved.'), 'ticket', p_ticket);

  perform public.fn_audit('reopen_ticket', 'ticket', p_ticket);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. trg_guard_stages — an assignee may not mark their own stage done
--
-- The guard listed assignment and schedule columns but not `status` or
-- `actual_*`, so the assignee (who legitimately has UPDATE on their own stage,
-- for the checklist) could set status='done' with a direct write and skip the
-- whole submit → approve chain. Progress and the client's view would say the
-- stage was approved when no PM had seen it.
--
-- The sanctioned transitions all run through SECURITY DEFINER RPCs
-- (fn_start_stage, fn_submit_stage, fn_decide_stage). Those triggers still fire
-- with the caller's auth.uid(), so each RPC marks the transaction as a
-- sanctioned one and the guard stands aside. Anything else — a direct UPDATE
-- from a client library — is refused.
-- ════════════════════════════════════════════════════════════════════════════

-- Marks the current transaction as a sanctioned stage transition. `true` makes
-- the setting transaction-local, so it can never leak into the next statement
-- on a pooled connection.
create or replace function public.fn_stage_rpc_begin() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('buildtrack.stage_rpc', 'on', true);
end $$;

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

drop trigger if exists t_guard_stages on stages;
create trigger t_guard_stages before update on stages
  for each row execute function public.trg_guard_stages();


-- The three sanctioned transitions, each re-declared to open the guard first.
-- Bodies are otherwise unchanged from 0009.

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

  perform public.fn_stage_rpc_begin();
  update stages
     set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
   where id = p_stage;

  perform public.fn_notify(v_pm, 'stage_started',
    v_code || ' · ' || v_stage || ' started',
    'Work has begun on this stage.', 'stage', p_stage);
end $$;


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
-- 6. The definer helpers are not a public API
--
-- fn_notify / fn_notify_client / fn_notify_role / fn_audit run as the table
-- owner and were granted to `authenticated` by default, so any signed-in user
-- could POST to /rpc/fn_notify and plant a notification in anyone's feed, or
-- write a false audit entry. They are only ever called from inside other
-- functions, which keep working: a SECURITY DEFINER function's body runs as its
-- owner, not as the caller.
--
-- fn_recompute_schedule / fn_refresh_all_statuses stay granted — the app calls
-- both directly. fn_stage_rpc_begin (§5) is revoked here for the same reason.
--
-- The role list is read from pg_roles, because `anon` exists on Supabase but
-- not on the plain Postgres the test suite runs against. (That suite also
-- re-grants everything to `authenticated` afterwards so the RLS tests can run
-- as real users, so this hardening is only observable on a real project.)
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare
  r record;
  v_roles text := 'public';
begin
  select v_roles || coalesce(string_agg(', ' || quote_ident(rolname), ''), '')
    into v_roles
    from pg_roles where rolname in ('authenticated', 'anon');

  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fn_notify','fn_notify_client','fn_notify_role','fn_audit',
                         'fn_stage_rpc_begin')
  loop
    execute format('revoke all on function %s from %s', r.sig, v_roles);
  end loop;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7. Store may create a catalogue item
--
-- Store logs parts at intake and keeps the inventory, so it hits "this item
-- isn't in the catalogue" more than anyone. item_catalog writes were
-- {admin,procurement,pm}, so Store's inline "new item" sheets (Stock → request,
-- Log component) failed on RLS with a permission error.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists item_catalog_write on public.item_catalog;
create policy item_catalog_write on public.item_catalog for all
  using      (public.has_role(array['admin','procurement','pm','store']))
  with check (public.has_role(array['admin','procurement','pm','store']));


-- ════════════════════════════════════════════════════════════════════════════
-- 8. A member owns their own name, phone and activation
--
-- profiles writes were admin-only, which broke two things:
--   • the set-password screen's `profiles.update(status:'active')` was silently
--     discarded (RLS filters the row out rather than erroring), so every
--     invited member stayed 'invited' forever — which reads as "never logged
--     in" on the Team screen;
--   • Settings → Account details had nothing it could save, which is why it was
--     a "coming soon" placeholder.
--
-- So: you may update your OWN row. Which columns is enforced by the trigger
-- below rather than by the policy, because a WITH CHECK can only see the new
-- row — it cannot tell which columns changed. Role, email, status-beyond-
-- activation, created_by and sub_team stay the admin's, so this can never be
-- used to self-promote.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists p_profiles_activate_self on public.profiles;
drop policy if exists p_profiles_update_self on public.profiles;
create policy p_profiles_update_self on public.profiles for update
  using      (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.trg_profiles_self_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.id is distinct from old.id then
    raise exception 'A profile id cannot change.' using errcode = '42501';
  end if;
  if new.id <> auth.uid() then return new; end if;   -- not the self-service path

  -- Yours to edit: full_name, phone, avatar_color — plus accepting the invite.
  if new.role        is distinct from old.role
     or new.email       is distinct from old.email
     or new.created_by  is distinct from old.created_by
     or new.sub_team_id is distinct from old.sub_team_id then
    raise exception 'Only an admin can change your role, email or team.' using errcode = '42501';
  end if;
  -- Status: invited → active only. Nobody re-enables their own disabled login.
  if new.status is distinct from old.status
     and not (old.status = 'invited' and new.status = 'active') then
    raise exception 'Only an admin can change your account status.' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_profiles_self_update on public.profiles;
create trigger t_profiles_self_update before update on public.profiles
  for each row execute function public.trg_profiles_self_update();


-- ════════════════════════════════════════════════════════════════════════════
-- 9. Design submission actually reaches the client
--
-- The app created an artifact and its first version with three separate client
-- writes (not atomic — a failure halfway left an artifact with no version and
-- no current_version_id), and nothing notified the client, while the screen
-- said "they've been notified". fn_create_design does the whole thing in one
-- transaction and notifies the client and the PM when it is submitted;
-- fn_add_design_version (0025) now notifies too.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_create_design(
  p_project     uuid,
  p_type        design_type,
  p_model_url   text    default null,
  p_image_url   text    default null,
  p_change_note text    default null,
  p_submit      boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_artifact uuid; v_version uuid; v_code text; v_pname text; v_pm uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can create a design.' using errcode = '42501';
  end if;

  select code, name, pm_id into v_code, v_pname, v_pm from projects where id = p_project;
  if v_code is null then raise exception 'Build not found.'; end if;

  insert into design_artifacts (project_id, type, status, created_by)
  values (p_project, p_type,
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


create or replace function public.fn_add_design_version(
  p_artifact    uuid,
  p_model_url   text default null,
  p_image_url   text default null,
  p_change_note text default null,
  p_submit      boolean default false)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_next int; v_id uuid; v_project uuid; v_type design_type;
  v_code text; v_pname text; v_pm uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can add a design version.' using errcode = '42501';
  end if;

  -- Lock the artifact row so concurrent version inserts for the SAME artifact
  -- serialise instead of colliding on version_no.
  select a.project_id, a.type into v_project, v_type
    from design_artifacts a where a.id = p_artifact for update;
  if not found then
    raise exception 'Design not found.';
  end if;

  select coalesce(max(version_no), 0) + 1 into v_next
    from design_versions where artifact_id = p_artifact;

  insert into design_versions (artifact_id, version_no, model_url, file_url, change_note)
    values (p_artifact, v_next, nullif(p_model_url, ''), nullif(p_image_url, ''), nullif(p_change_note, ''))
    returning id into v_id;

  update design_artifacts
     set current_version_id = v_id,
         status = (case when p_submit then 'pending_approval' else 'draft' end)::design_status,
         client_feedback = null
   where id = p_artifact;

  if p_submit then
    select code, name, pm_id into v_code, v_pname, v_pm from projects where id = v_project;
    perform public.fn_notify_client(v_project, 'design_submitted',
      'A revised design is ready for your approval',
      'The design team has shared version ' || v_next || ' of the ' || v_type ||
      ' design for ' || v_pname || '. Open the app to approve it or ask for changes.');
    perform public.fn_notify(v_pm, 'design_submitted',
      v_code || ' · ' || v_type || ' design v' || v_next || ' sent to the client',
      'The design team submitted a revision for client approval.', 'design', p_artifact);
  end if;

  return v_id;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 10. Offboarding a member must never fail on a foreign key
--
-- 0009 swept every FK pointing at profiles and made it ON DELETE SET NULL, but
-- 0017 and 0020 added seven more afterwards (purchase_orders.{pm_id,
-- submitted_by, pm_signed_by, final_signed_by, rejected_by},
-- po_approval_events.actor_id, stock_requests.requested_by). Removing a member
-- who had raised or signed a PO failed with a foreign-key violation. Same sweep,
-- re-run, so it also covers anything added later.
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
-- 11. An existing database has essentials
--
-- 0019 marks every bulk (non-serialized) item as a general essential, but it
-- only sweeps the rows that exist when it runs — so a database whose catalogue
-- was filled in afterwards has none, and Store's "request from procurement"
-- picker (which only offers essentials) is empty. This catches that up, and
-- only when NOTHING is essential yet, so it never clobbers a deliberate choice.
--
-- It cannot fix a *fresh* database: the migration chain finishes before seed.sql
-- runs, so this sweeps an empty table. The seed sets `is_essential` on its own
-- rows instead — see the comment there.
-- ════════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (select 1 from public.item_catalog where is_essential) then
    update public.item_catalog set is_essential = true where serialized = false;
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 12. A purchase order closes the demand it actually covers
--
-- fn_create_po only parked the ONE requirement passed as p_requirement, and only
-- the hero card on the To-Order list passes it. A PO raised from the blank "New
-- PO" button covered the same materials but left their requirements `pending`,
-- so the order-by alert kept firing for something already ordered — and
-- fn_recompute_status kept the build at_risk off that stale alert. Procurement
-- was being nagged to re-order what was on its way.
--
-- Now: after the lines are written, every still-pending requirement on this PO's
-- project whose item is on this PO is parked against it. The explicit
-- p_requirement still works and is still linked first (it also carries the
-- order-by deadline onto the PO), so nothing about the hero path changes.
-- A general (no-project) PO has no requirements to close, and fn_reject_po's
-- rework loop keeps them parked, exactly as before.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_create_po(
  p_vendor        uuid    default null,
  p_project       uuid    default null,
  p_order_date    date    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default '[]'::jsonb,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null,
  p_requirement   uuid    default null,
  p_stock_request uuid    default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_po       uuid;
  v_num      text;
  v_pm       uuid;
  v_appr     po_approval_status;
  v_needed   date;
  v_subtotal numeric := 0;
  v_tax      numeric := 0;
  v_line     jsonb;
  v_qty      int;
  v_price    numeric;
  v_rate     numeric;
  v_lt       numeric;
  v_linked   int := 0;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can raise a purchase order.' using errcode = '42501';
  end if;

  -- Route: a project PO needs the PM's signature first; a general PO does not.
  if p_project is not null then
    select pm_id into v_pm from projects where id = p_project;
  end if;
  v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Carry the order-by deadline through for delay flagging / priority.
  if p_requirement is not null then
    select order_by_date into v_needed from procurement_requirements where id = p_requirement;
  end if;

  -- Sum the lines up front for the header totals.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_qty   := coalesce((v_line->>'qty')::int, 1);
    v_price := coalesce((v_line->>'unit_price')::numeric, 0);
    v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
    v_lt    := v_qty * v_price;
    v_subtotal := v_subtotal + v_lt;
    v_tax      := v_tax + (v_lt * v_rate / 100.0);
  end loop;

  v_num := 'PO-' || to_char(nextval('public.po_number_seq'), 'FM00000');

  insert into purchase_orders (
    po_number, vendor_id, project_id, status, approval_status,
    order_date, delivery_date, needed_by, ship_to, payment_terms, notes,
    subtotal, tax_total, amount, pm_id, submitted_by, submitted_at, created_by)
  values (
    v_num, p_vendor, p_project, 'ordered', v_appr,
    coalesce(p_order_date, current_date), p_delivery_date, v_needed,
    nullif(btrim(coalesce(p_ship_to, '')), ''),
    nullif(btrim(coalesce(p_payment_terms, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''),
    v_subtotal, v_tax, v_subtotal + v_tax, v_pm, auth.uid(), now(), auth.uid())
  returning id into v_po;

  -- Lines.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
    values (
      v_po,
      (v_line->>'item_catalog_id')::uuid,
      coalesce((v_line->>'qty')::int, 1),
      coalesce((v_line->>'unit_price')::numeric, 0),
      coalesce((v_line->>'tax_rate')::numeric, 0),
      nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
      nullif(btrim(coalesce(v_line->>'description', '')), ''));
  end loop;

  -- Park the demand this PO fulfils so it leaves the To-Order list. If the PO
  -- is later rejected, fn_reject_po puts it back.
  if p_requirement is not null then
    update procurement_requirements set status = 'ordered', po_id = v_po where id = p_requirement;
  end if;
  if p_stock_request is not null then
    update stock_requests set status = 'ordered', po_id = v_po where id = p_stock_request;
  end if;

  -- …and the rest of the demand this PO actually covers, named by its lines.
  if p_project is not null then
    update procurement_requirements pr
       set status = 'ordered', po_id = v_po
     where pr.project_id = p_project
       and pr.status = 'pending'
       and pr.po_id is null
       and exists (select 1 from po_lines pl
                    where pl.po_id = v_po and pl.item_catalog_id = pr.item_catalog_id);
    get diagnostics v_linked = row_count;
    -- Closing an alert can take the build off at_risk.
    if v_linked > 0 or p_requirement is not null then
      perform public.fn_recompute_status(p_project);
    end if;
  end if;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (v_po, 'created', null, v_appr, auth.uid());

  -- Notify the next signer.
  if v_appr = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' needs your signature',
      'Procurement raised a purchase order on your build — review and sign it.',
      'purchase_order', v_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' needs final approval',
      'A purchase order is awaiting final sign-off.',
      'purchase_order', v_po, auth.uid());
  end if;

  perform public.fn_audit('create_po', 'purchase_order', v_po);
  return v_po;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 13. Handing a build to a new PM hands over the work in flight
--
-- `stage_approvals.approver_id` and `purchase_orders.pm_id` are snapshots taken
-- when the work was submitted. Reassigning a build left them pointing at the
-- old PM, so: the new PM's approvals queue was empty while the team waited, the
-- old PM (who no longer owns the build, and may have left) still held the
-- signature, and `fn_pm_sign_po` refused the new PM because `pm_id` wasn't them.
-- A PO only came unstuck if procurement happened to resubmit it.
--
-- So reassignment now moves the open items with the build. Decided approvals and
-- signed-off POs are history and are left exactly as they are — the trail must
-- keep saying who actually signed.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_assign_pm(p_project uuid, p_pm uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old uuid; v_code text; v_name text; v_role user_role; v_pstatus user_status;
  v_stages int := 0; v_pos int := 0;
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

  -- Work in flight moves to the new PM.
  update stage_approvals a
     set approver_id = p_pm
    from stages s
   where s.id = a.stage_id
     and s.project_id = p_project
     and a.status = 'pending';
  get diagnostics v_stages = row_count;

  update purchase_orders
     set pm_id = p_pm
   where project_id = p_project
     and approval_status in ('pending_pm','pending_final','rejected');
  get diagnostics v_pos = row_count;

  perform public.fn_notify(p_pm, 'project_assigned',
    v_code || ' is now yours',
    'You have been assigned as project manager for ' || v_name || '.' ||
    case when v_stages > 0 or v_pos > 0
      then ' Waiting on you: ' ||
           concat_ws(' and ',
             nullif(v_stages, 0) || ' stage approval(s)',
             nullif(v_pos, 0) || ' purchase order(s)') || '.'
      else ' Assign its stages to get the build moving.' end,
    'project', p_project);

  if v_old is not null then
    perform public.fn_notify(v_old, 'project_reassigned',
      v_code || ' was reassigned',
      v_name || ' now has a different project manager.', 'project', p_project);
  end if;

  perform public.fn_audit('assign_pm', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 14. A disabled account can read nothing
--
-- `profiles.status` was set and shown but never enforced: `my_role()` returned
-- the role regardless, so `is_staff()` / `has_role()` / `is_admin()` all said
-- yes and a disabled member who still had a valid session (or simply knew their
-- password — the auth user is untouched) could carry on using their role's
-- screens. Offboarding someone was a label, not a revocation.
--
-- Returning NULL for a disabled account makes every role test fail, which in
-- turn makes every RLS policy that depends on one deny. The app signs such a
-- user out at login with an explanation rather than dropping them into an empty
-- shell.
--
-- `invited` is deliberately still allowed: that is the state between the invite
-- and the password being set, and the set-password screen has to work.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.my_role() returns user_role
  language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() and status <> 'disabled' $$;

-- is_admin() must be strictly true/false, not three-valued.
--
-- `my_role()` can return NULL — now for a disabled account, and always for a
-- caller with no profile — and `select NULL = 'admin'` is NULL. RLS reads NULL
-- as false, so the policies were fine. plpgsql does not: `if not NULL then` is
-- *false*, so every `if not public.is_admin() then raise` guard in the RPCs was
-- silently skipped for a NULL role. A disabled admin walked straight through it,
-- and so did any caller with no JWT at all — which, since these functions are
-- SECURITY DEFINER and granted to PUBLIC, meant an anonymous POST to
-- /rpc/fn_assign_pm could reassign a build. coalesce closes both.
-- is_staff() and has_role() already coalesce, so nothing else changes.
--
-- **Behaviour change worth knowing:** fn_assign_pm, fn_onboard_project,
-- fn_final_approve_po and fn_set_po_priority now refuse a caller with no JWT —
-- so running them by hand in the Supabase SQL editor raises "Only an admin…".
-- Everything else (fn_recompute_schedule, fn_refresh_all_statuses, the daily
-- cron, the seed, the guard triggers' `auth.uid() is null` escape) is unaffected.
create or replace function public.is_admin() returns boolean
  language sql stable as $$ select coalesce(public.my_role() = 'admin', false) $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 15. Correct every build's status now, so the fixes above are visible without
--     waiting for the next edit or the daily cron.
-- ════════════════════════════════════════════════════════════════════════════

select public.fn_refresh_all_statuses();

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0027_po_needs_a_pm.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0027_po_needs_a_pm.sql
--
-- A purchase order on a build whose project manager has gone silently skipped
-- the PM's signature.
--
-- The routing rule is:
--
--     v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;
--
-- which reads "a general PO has no PM, so it goes straight to the owner" — and
-- that is right. What it also does, unintentionally, is treat *a project PO
-- whose build has no PM* as a general PO. One approval step disappears and
-- nothing says so: the PO lands in the owner's queue looking exactly like a
-- stock order, and the build's own manager never sees that money was committed
-- against their truck.
--
-- A build is supposed to always have a PM — `fn_onboard_project` refuses to
-- create one without it — but `profiles` carries `ON DELETE SET NULL` on
-- `projects.pm_id` (0009, so that offboarding a person can never fail on a
-- foreign key). So offboarding a PM leaves their builds PM-less, and from then
-- on every PO raised against them quietly loses a signature.
--
-- Both paths that route a PO now refuse instead, naming the fix. That strands
-- the PO until an admin assigns a PM — which is the correct outcome, because
-- the build is already stranded: its stages cannot be assigned or approved
-- either (`fn_submit_stage` has refused PM-less builds since 0009, with the
-- same reasoning and nearly the same sentence).
--
-- Idempotent: two function replacements, nothing else.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. Raising a PO
--
-- Body is 0026's, with the guard added after the PM lookup. Everything else —
-- totals, numbering, the requirement auto-link, the notifications — is
-- unchanged.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_create_po(
  p_vendor        uuid    default null,
  p_project       uuid    default null,
  p_order_date    date    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default '[]'::jsonb,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null,
  p_requirement   uuid    default null,
  p_stock_request uuid    default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_po       uuid;
  v_num      text;
  v_pm       uuid;
  v_code     text;
  v_appr     po_approval_status;
  v_needed   date;
  v_subtotal numeric := 0;
  v_tax      numeric := 0;
  v_line     jsonb;
  v_qty      int;
  v_price    numeric;
  v_rate     numeric;
  v_lt       numeric;
  v_linked   int := 0;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can raise a purchase order.' using errcode = '42501';
  end if;

  -- Route: a project PO needs the PM's signature first; a general PO does not.
  if p_project is not null then
    select pm_id, code into v_pm, v_code from projects where id = p_project;
    if v_code is null then
      raise exception 'That build does not exist.';
    end if;
    -- A build with no PM cannot take a PO: there is nobody to sign the first
    -- step, and routing it straight to the owner would drop that step without
    -- saying so.
    if v_pm is null then
      raise exception 'Build % has no project manager yet — ask an admin to assign one before raising a purchase order against it.', v_code;
    end if;
  end if;
  v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Carry the order-by deadline through for delay flagging / priority.
  if p_requirement is not null then
    select order_by_date into v_needed from procurement_requirements where id = p_requirement;
  end if;

  -- Sum the lines up front for the header totals.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_qty   := coalesce((v_line->>'qty')::int, 1);
    v_price := coalesce((v_line->>'unit_price')::numeric, 0);
    v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
    v_lt    := v_qty * v_price;
    v_subtotal := v_subtotal + v_lt;
    v_tax      := v_tax + (v_lt * v_rate / 100.0);
  end loop;

  v_num := 'PO-' || to_char(nextval('public.po_number_seq'), 'FM00000');

  insert into purchase_orders (
    po_number, vendor_id, project_id, status, approval_status,
    order_date, delivery_date, needed_by, ship_to, payment_terms, notes,
    subtotal, tax_total, amount, pm_id, submitted_by, submitted_at, created_by)
  values (
    v_num, p_vendor, p_project, 'ordered', v_appr,
    coalesce(p_order_date, current_date), p_delivery_date, v_needed,
    nullif(btrim(coalesce(p_ship_to, '')), ''),
    nullif(btrim(coalesce(p_payment_terms, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''),
    v_subtotal, v_tax, v_subtotal + v_tax, v_pm, auth.uid(), now(), auth.uid())
  returning id into v_po;

  -- Lines.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
    values (
      v_po,
      (v_line->>'item_catalog_id')::uuid,
      coalesce((v_line->>'qty')::int, 1),
      coalesce((v_line->>'unit_price')::numeric, 0),
      coalesce((v_line->>'tax_rate')::numeric, 0),
      nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
      nullif(btrim(coalesce(v_line->>'description', '')), ''));
  end loop;

  -- Park the demand this PO fulfils so it leaves the To-Order list. If the PO
  -- is later rejected, fn_reject_po puts it back.
  if p_requirement is not null then
    update procurement_requirements set status = 'ordered', po_id = v_po where id = p_requirement;
  end if;
  if p_stock_request is not null then
    update stock_requests set status = 'ordered', po_id = v_po where id = p_stock_request;
  end if;

  -- …and the rest of the demand this PO actually covers, named by its lines.
  if p_project is not null then
    update procurement_requirements pr
       set status = 'ordered', po_id = v_po
     where pr.project_id = p_project
       and pr.status = 'pending'
       and pr.po_id is null
       and exists (select 1 from po_lines pl
                    where pl.po_id = v_po and pl.item_catalog_id = pr.item_catalog_id);
    get diagnostics v_linked = row_count;
    if v_linked > 0 or p_requirement is not null then
      perform public.fn_recompute_status(p_project);
    end if;
  end if;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (v_po, 'created', null, v_appr, auth.uid());

  -- Notify the next signer.
  if v_appr = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' needs your signature',
      'Procurement raised a purchase order on your build — review and sign it.',
      'purchase_order', v_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' needs final approval',
      'A purchase order is awaiting final sign-off.',
      'purchase_order', v_po, auth.uid());
  end if;

  perform public.fn_audit('create_po', 'purchase_order', v_po);
  return v_po;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Resubmitting a rejected PO
--
-- Same hole on the way back round: a PO raised while the build had a PM, whose
-- PM was then offboarded, would re-enter the chain at the owner. Same refusal,
-- for the same reason. Body is 0026's otherwise.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_resubmit_po(
  p_po            uuid,
  p_vendor        uuid    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default null,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_appr po_approval_status; v_sub uuid; v_project uuid; v_pm uuid; v_num text;
  v_code text; v_next po_approval_status;
  v_subtotal numeric := 0; v_tax numeric := 0; v_line jsonb; v_qty int; v_price numeric; v_rate numeric; v_lt numeric;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can resubmit a purchase order.' using errcode = '42501';
  end if;

  select approval_status, submitted_by, project_id, po_number into v_appr, v_sub, v_project, v_num
    from purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_appr <> 'rejected' then
    raise exception 'Only a rejected purchase order can be resubmitted.';
  end if;

  if v_project is not null then
    select pm_id, code into v_pm, v_code from projects where id = v_project;
    if v_pm is null then
      raise exception 'Build % has no project manager yet — ask an admin to assign one before resubmitting this purchase order.', coalesce(v_code, '?');
    end if;
  end if;
  v_next := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Replace the lines + recompute the totals only when a new set is supplied.
  if p_lines is not null then
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_qty   := coalesce((v_line->>'qty')::int, 1);
      v_price := coalesce((v_line->>'unit_price')::numeric, 0);
      v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
      v_lt    := v_qty * v_price;
      v_subtotal := v_subtotal + v_lt;
      v_tax      := v_tax + (v_lt * v_rate / 100.0);
    end loop;

    delete from po_lines where po_id = p_po;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
      values (
        p_po,
        (v_line->>'item_catalog_id')::uuid,
        coalesce((v_line->>'qty')::int, 1),
        coalesce((v_line->>'unit_price')::numeric, 0),
        coalesce((v_line->>'tax_rate')::numeric, 0),
        nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
        nullif(btrim(coalesce(v_line->>'description', '')), ''));
    end loop;

    update purchase_orders
       set subtotal = v_subtotal, tax_total = v_tax, amount = v_subtotal + v_tax
     where id = p_po;
  end if;

  -- Header + wipe the signatures and re-enter the chain from the top. Every
  -- optional field keeps its current value when the caller passes null.
  update purchase_orders
     set vendor_id       = coalesce(p_vendor, vendor_id),
         delivery_date   = coalesce(p_delivery_date, delivery_date),
         payment_terms   = case when p_payment_terms is null then payment_terms
                                else nullif(btrim(p_payment_terms), '') end,
         notes           = case when p_notes is null then notes
                                else nullif(btrim(p_notes), '') end,
         ship_to         = case when p_ship_to is null then ship_to
                                else nullif(btrim(p_ship_to), '') end,
         approval_status = v_next, pm_id = v_pm,
         pm_signed_by = null, pm_signed_at = null,
         final_signed_by = null, final_signed_at = null,
         rejected_by = null, rejected_at = null, rejection_reason = null,
         submitted_by = auth.uid(), submitted_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (p_po, 'resubmitted', 'rejected', v_next, auth.uid());

  if v_next = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' was revised — please sign',
      'Procurement addressed the feedback and resubmitted this purchase order.',
      'purchase_order', p_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' was revised — needs approval',
      'A rejected purchase order has been revised and resubmitted.',
      'purchase_order', p_po, auth.uid());
  end if;

  perform public.fn_audit('resubmit_po', 'purchase_order', p_po);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0028_design_stage_link.sql
-- ═══════════════════════════════════════════════════════════════════════
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
--
-- The 0026 signature is dropped first. `create or replace` with an extra
-- parameter does not replace anything — it adds an overload, and since every
-- argument after p_type has a default, a four-argument call then matches both
-- and Postgres refuses it as ambiguous. (0015 hit the same thing adding an
-- argument to fn_recompute_schedule.)
drop function if exists public.fn_create_design(uuid, design_type, text, text, text, boolean);

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
    -- Its own type, not 'approved'/'revision': this notification is about the
    -- *stage*, and the designer already has one about the design. Two rows
    -- saying "approved" would read as the app repeating itself, and they lead
    -- to different places — one opens the design, this one opens the stage.
    perform public.fn_notify(r.assignee_id,
      case when p_approve then 'stage_ready' else 'stage_waiting' end,
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

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0029_checklist_is_evidence.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0029_checklist_is_evidence.sql
--
-- A stage's checklist was a to-do list pretending to be evidence.
--
-- The whole table was:
--
--     checklist_items (id, stage_id, label, done)
--
-- and the only way `done` ever moved was a bare `update checklist_items set
-- done = …` from the client. So nothing recorded **who** ticked a check or
-- **when**, there was nowhere to attach proof that the work was actually done,
-- the write never reached `fn_audit`, and a check on a stage the PM had already
-- approved could still be un-ticked — changing the evidence after sign-off.
--
-- Meanwhile `fn_install_component` — the other thing a fitter does on a stage —
-- *is* audited. Same stage, same person, two different standards.
--
-- This migration closes that, in three parts:
--
--   (b) The record, and the freeze. Every tick goes through `fn_tick_check`,
--       which writes `done_by` / `done_at` and audits it, and refuses on a
--       stage that is already approved. A direct UPDATE of `done` is refused
--       outright, the same way `trg_guard_stages` (0026) forces every stage
--       transition through its RPC.
--
--   (c) Proof where it matters. A check can be marked `photo_required` — on
--       the template, so every build inherits it, or on one build's stage by
--       its PM. Ticking such a check needs a photo on that stage, and the row
--       keeps which photo discharged it. Not every check: "weld the frame"
--       deserves a photo, "collect the keys" does not, and demanding one for
--       all of them is how a fitter learns to photograph the floor.
--
-- It also closes two gaps in the same family, both found reading the Workshop
-- role end to end:
--
--   * `fn_install_component` allowed a part into an **approved** stage, though
--     `fn_start_stage` and `fn_submit_stage` have both refused one since 0026.
--   * …and it silently stole a part another build had reserved (0026 made
--     Store's intake an earmark: `installed_in_project_id` set while `status`
--     stays `in_stock`). The earmark was overwritten and nobody was told.
--
--   * A workshop member could insert a `delay_logs` row against **any** stage
--     on any build, because the per-role matrix grants the table by role and
--     nothing narrowed it to their own work.
--
-- Idempotent: additive columns, one new RPC, four function replacements, one
-- trigger replacement, one policy replacement.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. The columns
--
-- `done_by` / `done_at` are the record. `photo_required` is the rule. and
-- `proof_attachment_id` is which photo discharged it — ON DELETE SET NULL,
-- because deleting a photo must not delete the check, but it must stop the
-- check claiming a photo that is gone.
-- ════════════════════════════════════════════════════════════════════════════

-- `done_by` is ON DELETE SET NULL, like every other nullable FK to profiles.
-- 0009 made that an invariant so that offboarding a person can never fail on a
-- foreign key, 0026 re-ran the sweep for the FKs added since, and
-- `80_hardening_tests.sql` H11 asserts it over the whole catalogue — which is
-- what caught this column declared without it. Nulling it is also the right
-- answer in itself: the tick stands, the record of who made it goes with the
-- person, and the row then reads the same as one ticked before 0029.
alter table public.checklist_items
  add column if not exists done_by             uuid references profiles(id) on delete set null,
  add column if not exists done_at             timestamptz,
  add column if not exists photo_required      boolean not null default false,
  add column if not exists proof_attachment_id uuid references attachments(id) on delete set null;

-- Belt and braces for a database where an earlier run of this migration added
-- the column without the rule (this file was corrected after its first CI run,
-- before it was applied anywhere). Matches 0026's sweep.
do $$
declare c text;
begin
  select con.conname into c
    from pg_constraint con
    join pg_attribute att
      on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
   where con.contype = 'f'
     and con.conrelid  = 'public.checklist_items'::regclass
     and con.confrelid = 'public.profiles'::regclass
     and con.confdeltype = 'a'
     and att.attname = 'done_by';
  if c is not null then
    execute format('alter table public.checklist_items drop constraint %I', c);
    execute 'alter table public.checklist_items
               add constraint checklist_items_done_by_fkey
               foreign key (done_by) references profiles(id) on delete set null';
  end if;
end $$;

comment on column public.checklist_items.done_by is
  'Who ticked this check. Written only by fn_tick_check.';
comment on column public.checklist_items.photo_required is
  'This check cannot be ticked without a photo on its stage. Set on the template, or by the build''s PM.';

-- Checks already ticked before this migration have no record to recover: the
-- old write stored nothing. Leaving done_by/done_at null is the honest state —
-- "ticked, by nobody we can name" — and the app says "before this was tracked"
-- rather than inventing an actor.

alter table public.template_stage_checks
  add column if not exists photo_required boolean not null default false;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. A template's photo rule reaches the build
--
-- Body is 0012's, with `photo_required` carried through step 1b. Everything
-- else — the stage copy, the backward schedule, the BOM, the notification — is
-- unchanged, and every step stays guarded so re-onboarding cannot duplicate.
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

  insert into stages (project_id, template_stage_id, name, ord, status, discipline)
  select p_project, ts.id, ts.name, ts.ord, 'todo',
         coalesce(ts.discipline, public.fn_infer_discipline(ts.name))
    from template_stages ts
   where ts.template_id = v_template
     and not exists (select 1 from stages s where s.project_id = p_project);

  -- 1b) checklist for each stage, now carrying the template's photo rule.
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


-- ════════════════════════════════════════════════════════════════════════════
-- 3. Ticking a check is an action, not a field write
--
-- Same shape as the stage RPCs: the function marks the transaction sanctioned
-- and the guard stands aside for it. `true` keeps the setting
-- transaction-local, so it can never leak into the next statement on a pooled
-- connection.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_check_rpc_begin() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('buildtrack.check_rpc', 'on', true);
end $$;

-- Revoked from callers for the same reason 0026 revokes fn_stage_rpc_begin: a
-- client that could set the flag itself could then write `done` directly and
-- the record would be back to being optional. The role list is read from
-- pg_roles because `anon` exists on Supabase and not on the plain Postgres the
-- test suite runs against — and that suite re-grants everything to
-- `authenticated` afterwards, so this is only observable on a real project.
do $$
declare v_roles text := 'public';
begin
  select v_roles || coalesce(string_agg(', ' || quote_ident(rolname), ''), '')
    into v_roles
    from pg_roles where rolname in ('authenticated', 'anon');
  execute format('revoke all on function public.fn_check_rpc_begin() from %s', v_roles);
end $$;

create or replace function public.fn_tick_check(
  p_item  uuid,
  p_done  boolean,
  p_proof uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage    uuid;
  v_label    text;
  v_needs    boolean;
  v_sstatus  stage_status;
  v_assignee uuid;
  v_pm       uuid;
  v_code     text;
  v_sname    text;
  v_proof    uuid;
begin
  select ci.stage_id, ci.label, ci.photo_required,
         s.status, s.assignee_id, s.name, p.pm_id, p.code
    into v_stage, v_label, v_needs, v_sstatus, v_assignee, v_sname, v_pm, v_code
    from checklist_items ci
    join stages   s on s.id = ci.stage_id
    join projects p on p.id = s.project_id
   where ci.id = p_item;
  if v_stage is null then raise exception 'Checklist item not found.'; end if;

  -- Who may tick: the person doing the work, their PM, or an admin. Same set
  -- as the p_check_write policy, named here so the RPC refuses before the
  -- policy does and the message says something useful.
  if not (public.is_admin() or v_assignee = auth.uid() or v_pm = auth.uid()) then
    raise exception 'Only the member assigned to this stage can tick its checklist.'
      using errcode = '42501';
  end if;

  -- (b) The freeze. Once the PM has approved the stage its checklist is the
  -- evidence they approved, and evidence that can still be edited is not
  -- evidence. An admin is let through deliberately: correcting a genuine
  -- mistake on a closed build is their job, and fn_audit records that it was
  -- them.
  if v_sstatus = 'done' and not public.is_admin() then
    raise exception 'This stage is already approved as complete — its checklist is part of the approval and cannot be changed.';
  end if;

  if p_done then
    -- (c) Proof where the check asks for it.
    if coalesce(v_needs, false) then
      if p_proof is null then
        raise exception 'Check "%" needs a photo before it can be ticked — take one on this stage first.', v_label;
      end if;
      -- The photo has to be on *this* stage. Without this the id of any
      -- attachment in the system would satisfy the rule.
      if not exists (select 1 from attachments a
                      where a.id = p_proof
                        and a.owner_type = 'stage'
                        and a.owner_id = v_stage) then
        raise exception 'That photo is not on this stage.';
      end if;
    end if;
    v_proof := p_proof;
  else
    -- Un-ticking drops the record with it: a check that is not done was not
    -- done by anybody, and leaving a stale name on it reads as if it were.
    v_proof := null;
  end if;

  perform public.fn_check_rpc_begin();
  update checklist_items
     set done                = p_done,
         done_by             = case when p_done then auth.uid() else null end,
         done_at             = case when p_done then now() else null end,
         proof_attachment_id = v_proof
   where id = p_item;

  perform public.fn_audit(
    case when p_done then 'tick_check' else 'untick_check' end,
    'checklist_item', p_item);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. The guard
--
-- 0028 handed the *wording* of a checklist to the PM. This adds the three
-- things that make the tick itself trustworthy:
--
--   * `done` and its record move only inside fn_tick_check. A client that
--     writes the column directly is refused, so the audit trail has no hole.
--   * `photo_required` is the PM's to set, like the label.
--   * an approved stage's checklist is closed to everyone but an admin —
--     including to adding and removing items, which 0028 left open to the PM.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_guard_checklist() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_stage uuid; v_sstatus stage_status; v_row record; v_sanctioned boolean;
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

  v_sanctioned := coalesce(current_setting('buildtrack.check_rpc', true), '') = 'on';

  select p.pm_id, s.status into v_pm, v_sstatus
    from stages s join projects p on p.id = s.project_id
   where s.id = v_stage;

  -- An approved stage's checklist is the evidence the PM signed off on. Not
  -- even they may rewrite it now; an admin can, and fn_audit records it.
  -- fn_tick_check refuses this case too, with a sentence about the approval —
  -- this is the backstop for a direct write.
  if v_sstatus = 'done' then
    raise exception 'This stage is already approved as complete — its checklist cannot be changed.'
      using errcode = '42501';
  end if;

  -- Ticking: only ever through fn_tick_check, so done_by / done_at / the proof
  -- are always written together and always audited.
  if tg_op = 'UPDATE' and not v_sanctioned
     and (new.done                is distinct from old.done
       or new.done_by             is distinct from old.done_by
       or new.done_at             is distinct from old.done_at
       or new.proof_attachment_id is distinct from old.proof_attachment_id) then
    raise exception 'Tick a checklist item through fn_tick_check, so who ticked it and when is recorded.'
      using errcode = '42501';
  end if;

  if v_pm = auth.uid() then return v_row; end if;

  if tg_op = 'INSERT' then
    raise exception 'Only the project manager can add items to a stage checklist.'
      using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Only the project manager can remove items from a stage checklist.'
      using errcode = '42501';
  elsif new.label          is distinct from old.label
     or new.stage_id       is distinct from old.stage_id
     or new.photo_required is distinct from old.photo_required then
    raise exception 'Only the project manager can change what a checklist item says, or whether it needs a photo.'
      using errcode = '42501';
  end if;

  return v_row;
end $$;

drop trigger if exists t_guard_checklist on public.checklist_items;
create trigger t_guard_checklist before insert or update or delete on public.checklist_items
  for each row execute function public.trg_guard_checklist();


-- ════════════════════════════════════════════════════════════════════════════
-- 5. A part cannot be fitted into an approved stage, or taken off another build
--
-- Body is 0009's, with two guards added after the stock check. The caller
-- check, the status check and the audit are unchanged.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_install_component(p_component uuid, p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_project  uuid; v_assignee uuid; v_cstatus component_status;
  v_serial   text; v_code text; v_sstatus stage_status;
  v_reserved uuid; v_rcode text;
begin
  select s.project_id, s.assignee_id, s.status, p.code
    into v_project, v_assignee, v_sstatus, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid() or public.has_role(array['store'])) then
    raise exception 'Only the member assigned to this stage can install parts into it.' using errcode = '42501';
  end if;

  -- An approved stage is closed. fn_start_stage and fn_submit_stage have both
  -- refused one since 0026; this did not, so a part could be added to the
  -- record of a stage the PM had already signed off — and the truck record and
  -- the client's build timeline both changed after the approval.
  if v_sstatus = 'done' then
    raise exception 'That stage is already approved as complete — a part cannot be added to it now.';
  end if;

  select status, serial_number, installed_in_project_id
    into v_cstatus, v_serial, v_reserved
    from component_instances where id = p_component;
  if v_cstatus is null then raise exception 'That component is not in the system — ask Store to log it first.'; end if;
  if v_cstatus <> 'in_stock' then
    raise exception 'Serial % is marked % — only in-stock parts can be installed.', coalesce(v_serial, '?'), v_cstatus;
  end if;

  -- An in-stock part that already names a build is Store's earmark for that
  -- build (0026: intake reserves, it does not install). Fitting it elsewhere
  -- used to overwrite the earmark silently, so the build it was bought for
  -- lost its part and nobody was told.
  if v_reserved is not null and v_reserved <> v_project then
    select code into v_rcode from projects where id = v_reserved;
    raise exception 'Serial % is reserved for % — ask Store to release it before fitting it to %.',
      coalesce(v_serial, '?'), coalesce(v_rcode, 'another build'), v_code;
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


-- ════════════════════════════════════════════════════════════════════════════
-- 6. A delay is reported against your own work
--
-- The per-role matrix grants `delay_logs` to {admin,pm,workshop} — and giving
-- the fitter a way to say "the steel did not arrive" is right, because they are
-- the one who knows. But the grant is by role, so any workshop member could
-- log a delay against any stage on any build, including one they have never
-- seen. Narrowed to their own stage; admin and the build's PM keep the full
-- table, since attributing a slip across the build is the PM's job.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists delay_logs_write on public.delay_logs;
create policy delay_logs_write on public.delay_logs for all
  using (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id))
  with check (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id));

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0030_a_photo_is_evidence_too.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0030_a_photo_is_evidence_too.sql
--
-- 0029 made a checklist tick evidence: recorded, optionally photo-backed, and
-- frozen once the PM approves. It left the photos themselves wide open.
--
-- `attachments` has carried one policy since 0002:
--
--     create policy p_att_staff on attachments for all using (public.is_staff())
--
-- so **any** staff member — a welder on another build, store, procurement —
-- could delete any photo on any stage of any truck. Nothing recorded it, and
-- nothing stopped it after the PM had approved the stage and signed off on
-- those very photos as the evidence. A check whose proof can be deleted by a
-- passer-by is not proof, which makes 0029's rule only half a rule.
--
-- The stage screen is also about to offer "delete" on a photo for the first
-- time (until now a photo could be added and never removed, which is its own
-- problem: a fitter who uploads the wrong shot had no way back). Offering it
-- without a rule behind it would be the same mistake as the bare `done`
-- column.
--
-- So: deleting a stage photo is for the person who took it, the build's PM, or
-- an admin — and once the stage is approved, only an admin, exactly as the
-- checklist freezes. Adding one is unchanged. Tickets and designs keep their
-- own policies and are untouched.
--
-- Idempotent: one function, one trigger.


create or replace function public.trg_guard_attachments() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_sstatus stage_status; v_uploader uuid;
begin
  -- No JWT = service role / SQL editor / seed, as everywhere else.
  if auth.uid() is null then return old; end if;
  if public.is_admin() then return old; end if;

  -- Only stage photos are governed here. A ticket photo belongs to the client
  -- who raised it and a design file to its version; both have their own rules.
  if old.owner_type <> 'stage' then return old; end if;

  select p.pm_id, s.status into v_pm, v_sstatus
    from stages s join projects p on p.id = s.project_id
   where s.id = old.owner_id;

  -- An attachment pointing at a stage that no longer exists is orphaned; let
  -- it go rather than stranding it forever.
  if v_pm is null and v_sstatus is null then return old; end if;

  if v_sstatus = 'done' then
    raise exception 'This stage is already approved as complete — its photos are part of that approval.'
      using errcode = '42501';
  end if;

  v_uploader := old.uploaded_by;
  if not (v_uploader = auth.uid() or v_pm = auth.uid()) then
    raise exception 'Only whoever took this photo, or the build''s project manager, can remove it.'
      using errcode = '42501';
  end if;

  return old;
end $$;

drop trigger if exists t_guard_attachments on public.attachments;
create trigger t_guard_attachments before delete on public.attachments
  for each row execute function public.trg_guard_attachments();

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0031_stages_run_in_steps.sql
-- ═══════════════════════════════════════════════════════════════════════
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

-- Deliberately **no default**. `step` left unset means "its own step", which
-- every reader spells `coalesce(step, ord)` — not "step 1", which is what a
-- default of 1 would mean and which quietly makes an entire build parallel.
-- An insert that forgets the column is the normal case (every existing test
-- fixture, and seed.sql, which runs *after* this migration), so the safe
-- reading of a missing value has to be the sequential one.
alter table public.stages          alter column step drop default;
alter table public.template_stages alter column step drop default;

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

  -- 1b) checklist for each stage, carrying the template's photo rule (0029).
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

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0032_designations_and_who_created_a_build.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0032_designations_and_who_created_a_build.sql
--
-- Two small facts the app had nowhere to put.
--
-- **A designation.** `profiles.role` says which department somebody is in —
-- admin, pm, workshop — and that is what every permission is built on. It does
-- not say what they *do* there, and a growing company needs both: two admins
-- may be Operations and Finance, two workshop members a supervisor and a
-- fitter. The role stays the permission; the designation is what people call
-- each other, shown wherever a name is.
--
-- `is_supervisor` is the one piece of it the app has to *act* on rather than
-- display: a workshop supervisor is who a project manager hands workshop work
-- to, and who then breaks it down for their own people. Kept as a flag rather
-- than a magic designation string so the rule never depends on how somebody
-- typed a job title, and deliberately not a `user_role`, because a supervisor
-- is still workshop — every stage rule, every discipline match and every RLS
-- policy for them is the workshop one.
--
-- **Who created a build.** With one admin it was obvious. With several, the
-- owner wants to filter the fleet by the admin who onboarded each build — and
-- nothing recorded it. `fn_audit('onboard_project', …)` has the trail, but the
-- audit log is admin-only, unindexed for this, and not what a list should be
-- filtered on.
--
-- Idempotent: three additive columns, one backfill from the audit log.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. What somebody does, beside what they may do
-- ════════════════════════════════════════════════════════════════════════════

alter table public.profiles
  add column if not exists designation   text,
  add column if not exists is_supervisor boolean not null default false;

comment on column public.profiles.designation is
  'What this person does — "Operations", "Senior Fitter". Display only; `role` remains the permission.';
comment on column public.profiles.is_supervisor is
  'A workshop supervisor: the person a PM hands workshop work to, who then assigns it on. Not a role — they are still workshop.';

-- A supervisor only means anything inside workshop. Nothing enforces a
-- department on a free-text designation, but this one drives behaviour, so it
-- is worth being exact about.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_supervisor_is_workshop') then
    alter table public.profiles
      add constraint profiles_supervisor_is_workshop
      check (not is_supervisor or role = 'workshop') not valid;
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Which admin brought this build in
-- ════════════════════════════════════════════════════════════════════════════

alter table public.projects
  add column if not exists created_by uuid references profiles(id) on delete set null;

comment on column public.projects.created_by is
  'The admin who onboarded this build. ON DELETE SET NULL like every other nullable FK to profiles (0009).';

create index if not exists idx_projects_created_by on public.projects(created_by);

-- Backfill from the audit log, which has recorded this since 0009 even though
-- nothing could read it usefully. Builds onboarded before auditing, or whose
-- admin has since been offboarded, keep a null — which the filter shows as
-- "Not recorded" rather than guessing.
update public.projects p
   set created_by = a.actor_id
  from (
    select distinct on (entity_id) entity_id, actor_id
      from audit_log
     where action = 'onboard_project'
       and entity_type = 'project'
       and actor_id is not null
     order by entity_id, created_at
  ) a
 where a.entity_id = p.id
   and p.created_by is null;

-- New builds record it as they are created. `auth.uid()` is the admin doing it;
-- a row written with no JWT (seed, SQL editor) simply has none.
create or replace function public.trg_project_created_by() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists t_project_created_by on public.projects;
create trigger t_project_created_by before insert on public.projects
  for each row execute function public.trg_project_created_by();

-- ════════════════════════════════════════════════════════════════════════════
-- 3. Neither of these is yours to set about yourself
--
-- 0026 let a member edit their own row — name, phone, avatar, and accepting an
-- invite — with a trigger holding role, email, team and status on the admin's
-- side. Two new columns land in that same gap, and one of them *matters*:
-- `is_supervisor` decides who a PM can hand workshop work to and who may then
-- assign it on. Left unguarded, any workshop member could promote themselves.
--
-- Body is 0026's, with the two columns added to the list. Nothing else changes.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_profiles_self_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.id is distinct from old.id then
    raise exception 'A profile id cannot change.' using errcode = '42501';
  end if;
  if new.id <> auth.uid() then return new; end if;   -- not the self-service path

  -- Yours to edit: full_name, phone, avatar_color — plus accepting the invite.
  if new.role        is distinct from old.role
     or new.email       is distinct from old.email
     or new.created_by  is distinct from old.created_by
     or new.sub_team_id is distinct from old.sub_team_id
     or new.designation   is distinct from old.designation
     or new.is_supervisor is distinct from old.is_supervisor then
    raise exception 'Only an admin can change your role, email, team or designation.' using errcode = '42501';
  end if;
  -- Status: invited → active only. Nobody re-enables their own disabled login.
  if new.status is distinct from old.status
     and not (old.status = 'invited' and new.status = 'active') then
    raise exception 'Only an admin can change your account status.' using errcode = '42501';
  end if;
  return new;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0033_workshop_sub_stages.sql
-- ═══════════════════════════════════════════════════════════════════════
-- 0033_workshop_sub_stages.sql
--
-- A workshop stage is one line in the project's pipeline and a fortnight of
-- work on the floor. "Workshop" covers the structural framework, the hole
-- drilling, the cladding, the paint, the branding, the electricals, the
-- insulation, the flooring, the fittings, the plumbing, the finishing — each
-- done by different people, several of them at the same time.
--
-- The project manager should not be assigning fifteen of those by name on
-- forty builds; the workshop knows its own people. So a PM hands the stage to
-- a **supervisor** (0032's flag) and says what the truck needs, and the
-- supervisor breaks it into **sub-stages** and gives each one to somebody.
--
-- Sub-stages borrow two ideas that already work rather than inventing any:
--
--   * `step`, exactly as 0031 gave it to stages — same step runs together, a
--     step opens when every earlier one is done. The supervisor sets it, so
--     *they* decide what runs alongside what on this truck, not the template.
--   * `done_by` / `done_at`, exactly as 0029 gave the checklist — who did it
--     and when, recorded by the RPC rather than written by a client.
--
-- What they deliberately do **not** borrow is the evidence machinery. The
-- stage already has a checklist that can demand photos and a photo gallery the
-- PM and client see; a second one hanging off sub-stages would be two places
-- to look for the same thing. A sub-stage answers "who is doing this, and is
-- it done" — the stage still answers "is there proof".
--
-- Idempotent: one enum, one table, one trigger, one RPC.


-- Guarded: the test harness re-applies the newest migration to prove it is
-- idempotent, and `create type` has no `if not exists`.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'task_status') then
    create type task_status as enum ('todo', 'in_progress', 'done');
  end if;
end $$;

create table if not exists public.stage_tasks (
  id          uuid primary key default gen_random_uuid(),
  stage_id    uuid not null references stages(id) on delete cascade,
  title       text not null,
  ord         int  not null default 0,
  -- Same meaning as stages.step (0031): sub-stages sharing a step run
  -- alongside each other. Null = its own step, which is `ord`.
  step        int,
  assignee_id uuid references profiles(id) on delete set null,
  status      task_status not null default 'todo',
  -- Who marked it done, and when. Written only by fn_set_task_status.
  done_by     uuid references profiles(id) on delete set null,
  done_at     timestamptz,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists idx_stage_tasks_stage    on public.stage_tasks(stage_id, ord);
create index if not exists idx_stage_tasks_assignee on public.stage_tasks(assignee_id);

comment on table public.stage_tasks is
  'The supervisor''s breakdown of a stage into work for individual people. Not the checklist: that is the PM''s condition for approving the stage.';

alter table public.stage_tasks enable row level security;


-- ════════════════════════════════════════════════════════════════════════════
-- 1. Who may touch one
--
-- Read: any staff member — the PM watches progress, the client's own screens
-- never see these. Write: the people who own the stage, plus the person the
-- sub-stage was given to, who may move only its status. The trigger below
-- draws that second line; the policy only has to get them through the door.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists stage_tasks_read  on public.stage_tasks;
drop policy if exists stage_tasks_write on public.stage_tasks;

create policy stage_tasks_read on public.stage_tasks
  for select using (public.is_staff());

create policy stage_tasks_write on public.stage_tasks
  for all
  using (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id)
    or assignee_id = auth.uid())
  with check (
    public.is_admin()
    or public.is_pm_of_stage(stage_id)
    or public.is_stage_assignee(stage_id)
    or assignee_id = auth.uid());


-- ════════════════════════════════════════════════════════════════════════════
-- 2. The plan is the supervisor's; the status is whoever is doing it
--
-- Same shape as trg_guard_checklist (0029): the person doing the work may say
-- it is done and nothing else. What a sub-stage *says*, who it is for and what
-- it runs alongside are the supervisor's — otherwise a worker could hand their
-- own job to somebody else, or quietly move it out of the way of the step that
-- was waiting on it.
--
-- And, like a checklist, an approved stage's breakdown is closed: it is part
-- of what the PM signed off.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_task_rpc_begin() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('buildtrack.task_rpc', 'on', true);
end $$;

do $$
declare v_roles text := 'public';
begin
  select v_roles || coalesce(string_agg(', ' || quote_ident(rolname), ''), '')
    into v_roles
    from pg_roles where rolname in ('authenticated', 'anon');
  execute format('revoke all on function public.fn_task_rpc_begin() from %s', v_roles);
end $$;

create or replace function public.trg_guard_stage_tasks() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_assignee uuid; v_sstatus stage_status; v_stage uuid; v_row record;
begin
  if tg_op = 'DELETE' then
    v_row := old; v_stage := old.stage_id;
  else
    v_row := new; v_stage := new.stage_id;
  end if;

  -- No JWT = service role / SQL editor / seed, as everywhere else.
  if auth.uid() is null then return v_row; end if;
  if public.is_admin() then return v_row; end if;

  select p.pm_id, s.assignee_id, s.status
    into v_pm, v_assignee, v_sstatus
    from stages s join projects p on p.id = s.project_id
   where s.id = v_stage;

  -- An approved stage's breakdown is part of what was approved.
  if v_sstatus = 'done' then
    raise exception 'This stage is already approved as complete — its work items cannot be changed.'
      using errcode = '42501';
  end if;

  -- The supervisor the stage was given to, and the build's PM, own the plan.
  if v_assignee = auth.uid() or v_pm = auth.uid() then return v_row; end if;

  if tg_op = 'INSERT' then
    raise exception 'Only the supervisor this stage was assigned to can add work items.'
      using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Only the supervisor this stage was assigned to can remove work items.'
      using errcode = '42501';
  end if;

  -- Left: the person it was given to. Status is theirs; everything else is not.
  if old.assignee_id is distinct from auth.uid() then
    raise exception 'This work item is not yours.' using errcode = '42501';
  end if;
  if new.title       is distinct from old.title
     or new.step        is distinct from old.step
     or new.ord         is distinct from old.ord
     or new.assignee_id is distinct from old.assignee_id
     or new.stage_id    is distinct from old.stage_id then
    raise exception 'Only the supervisor can change what a work item says, who it is for, or what it runs alongside.'
      using errcode = '42501';
  end if;
  if (new.status is distinct from old.status
      or new.done_by is distinct from old.done_by
      or new.done_at is distinct from old.done_at)
     and coalesce(current_setting('buildtrack.task_rpc', true), '') <> 'on' then
    raise exception 'Move a work item through fn_set_task_status, so who finished it and when is recorded.'
      using errcode = '42501';
  end if;

  return v_row;
end $$;

drop trigger if exists t_guard_stage_tasks on public.stage_tasks;
create trigger t_guard_stage_tasks before insert or update or delete on public.stage_tasks
  for each row execute function public.trg_guard_stage_tasks();


-- ════════════════════════════════════════════════════════════════════════════
-- 3. Moving one
--
-- Records who finished it, refuses one whose turn has not come, and audits.
-- The step gate is 0031's rule applied inside a stage: everything in an
-- earlier sub-step has to be done first.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_set_task_status(p_task uuid, p_status task_status)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage uuid; v_title text; v_step int; v_assignee uuid;
  v_sassignee uuid; v_pm uuid; v_sstatus stage_status;
  v_open int; v_blocker text;
begin
  select t.stage_id, t.title, coalesce(t.step, t.ord), t.assignee_id,
         s.assignee_id, s.status, p.pm_id
    into v_stage, v_title, v_step, v_assignee, v_sassignee, v_sstatus, v_pm
    from stage_tasks t
    join stages   s on s.id = t.stage_id
    join projects p on p.id = s.project_id
   where t.id = p_task;
  if v_stage is null then raise exception 'Work item not found.'; end if;

  if not (public.is_admin()
          or v_assignee  = auth.uid()
          or v_sassignee = auth.uid()
          or v_pm        = auth.uid()) then
    raise exception 'Only the person this work item was given to, or their supervisor, can move it.'
      using errcode = '42501';
  end if;

  if v_sstatus = 'done' and not public.is_admin() then
    raise exception 'This stage is already approved as complete — its work items cannot be changed.';
  end if;

  -- The gate, inside the stage. An admin is let through: putting a build back
  -- in order is their job, and fn_audit records that it was them.
  if p_status <> 'todo' and not public.is_admin() then
    select count(*), min(e.title)
      into v_open, v_blocker
      from stage_tasks e
     where e.stage_id = v_stage
       and coalesce(e.step, e.ord) < v_step
       and e.status <> 'done';
    if coalesce(v_open, 0) > 0 then
      raise exception '% cannot start yet — % still has to be finished first.',
        v_title,
        case when v_open = 1 then coalesce(v_blocker, 'an earlier item')
             else v_open || ' earlier items' end;
    end if;
  end if;

  perform public.fn_task_rpc_begin();
  update stage_tasks
     set status  = p_status,
         done_by = case when p_status = 'done' then auth.uid() else null end,
         done_at = case when p_status = 'done' then now() else null end
   where id = p_task;

  perform public.fn_audit('set_task_status', 'stage_task', p_task);
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- migrations/0034_workflow_templates.sql
-- ═══════════════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════════════
-- seed.sql — demo data (safe to delete this section for a clean install)
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — demo seed data
-- NOTE: user (profiles) rows are created via Supabase Auth signup and mapped by trigger.
-- This seed populates domain data with user-FKs left NULL so it runs standalone.

-- ===== workflow template =====
insert into workflow_templates (id, name, truck_type) values
  ('11111111-0000-0000-0000-000000000001','Standard Food Truck','food_truck');

-- `step` says what waits for what (0031); `ord` is only the order they are
-- listed in. This workflow is strictly sequential — one stage per step — which
-- is how every build behaved before steps existed. A template that wanted the
-- cladding and the electricals to run alongside each other would give them the
-- same step.
insert into template_stages (template_id, name, ord, step, default_duration_days) values
  ('11111111-0000-0000-0000-000000000001','Design & Layout',1,1,4),
  ('11111111-0000-0000-0000-000000000001','Chassis & Structure',2,2,7),
  ('11111111-0000-0000-0000-000000000001','Exterior cladding',3,3,3),
  ('11111111-0000-0000-0000-000000000001','Electrical work',4,4,4),
  ('11111111-0000-0000-0000-000000000001','Interior & Equipment',5,5,3),
  ('11111111-0000-0000-0000-000000000001','Paint & Branding',6,6,2),
  ('11111111-0000-0000-0000-000000000001','Testing & Delivery',7,7,2);

-- ===== vendors =====
insert into vendors (id, name, category, avg_lead_time_days, reliability_score) values
  ('22222222-0000-0000-0000-000000000001','Sharma Traders','Electronics',4,92),
  ('22222222-0000-0000-0000-000000000002','Metro Steel','Fabrication',6,78),
  ('22222222-0000-0000-0000-000000000003','Kirana Elec','Electricals',3,88),
  ('22222222-0000-0000-0000-000000000004','Delhi Imports','Imported',45,64);

-- ===== item catalog =====
--
-- is_essential is set explicitly, not left to 0019's backfill. 0019 runs as part
-- of the migration chain, which finishes BEFORE this file — so on a fresh
-- database (and in full_setup.sql, which concatenates the two in that order) its
-- `update … where serialized = false` sweeps an empty table, and every item
-- seeded here lands with the column's `false` default. The visible symptom was
-- Store's "Request from procurement" picker being empty on every demo database,
-- because that picker only offers essentials.
insert into item_catalog (id, name, model, category, default_vendor_id, lead_time_days, buffer_days, serialized, is_essential) values
  ('33333333-0000-0000-0000-000000000001','Samsung 42" TV','UA42-XYZ','Electronics','22222222-0000-0000-0000-000000000001',3,1,true,false),
  ('33333333-0000-0000-0000-000000000002','Inverter 2kW',null,'Electricals','22222222-0000-0000-0000-000000000003',3,1,true,false),
  ('33333333-0000-0000-0000-000000000003','Espresso machine (custom)',null,'Equipment','22222222-0000-0000-0000-000000000004',45,5,true,false),
  -- Bulk stock the Store reorders on its own, regardless of any one build.
  ('33333333-0000-0000-0000-000000000004','Steel sheet 4x8',null,'Fabrication','22222222-0000-0000-0000-000000000002',6,2,false,true);

insert into stock_items (item_catalog_id, quantity, unit) values
  ('33333333-0000-0000-0000-000000000004',42,'sheets');

-- ===== client + project =====
insert into client_accounts (id, business_name, phone) values
  ('44444444-0000-0000-0000-000000000001','Ramesh Traders','+91-90000-00001');

insert into projects (id, code, name, client_account_id, template_id, status, target_delivery_date, advance_received) values
  ('55555555-0000-0000-0000-000000000001','AZ-118','Chai Point Truck',
   '44444444-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','on_track','2026-08-30',true);

-- stages for AZ-118 (mirrors template)
insert into stages (project_id, template_stage_id, name, ord, status)
select '55555555-0000-0000-0000-000000000001', ts.id, ts.name, ts.ord,
       case when ts.ord < 4 then 'done'::stage_status
            when ts.ord = 4 then 'in_progress'::stage_status
            else 'todo'::stage_status end
from template_stages ts
where ts.template_id = '11111111-0000-0000-0000-000000000001';

-- procurement requirements
insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, status) values
  ('55555555-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000003',1,'2026-08-22','pending'),
  ('55555555-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000001',1,'2026-08-23','pending');

-- an installed, traceable component (Samsung TV on a delivered truck AZ-098-like demo → here on AZ-118)
insert into component_instances
  (item_catalog_id, serial_number, vendor_id, bill_url, warranty_start, warranty_end, status, installed_in_project_id, install_date)
values
  ('33333333-0000-0000-0000-000000000001','SN-88213-KD','22222222-0000-0000-0000-000000000001',
   'https://storage/bills/SN-88213-KD.pdf','2026-08-12','2028-08-11','installed',
   '55555555-0000-0000-0000-000000000001','2026-08-12');

-- compute schedule + order-by dates + progress
select public.fn_recompute_schedule('55555555-0000-0000-0000-000000000001');
select public.fn_recompute_progress('55555555-0000-0000-0000-000000000001');

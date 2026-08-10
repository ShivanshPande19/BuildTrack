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
-- seed.sql — demo data (safe to delete this section for a clean install)
-- ═══════════════════════════════════════════════════════════════════════
-- Azimuth BuildTrack — demo seed data
-- NOTE: user (profiles) rows are created via Supabase Auth signup and mapped by trigger.
-- This seed populates domain data with user-FKs left NULL so it runs standalone.

-- ===== workflow template =====
insert into workflow_templates (id, name, truck_type) values
  ('11111111-0000-0000-0000-000000000001','Standard Food Truck','food_truck');

insert into template_stages (template_id, name, ord, default_duration_days) values
  ('11111111-0000-0000-0000-000000000001','Design & Layout',1,4),
  ('11111111-0000-0000-0000-000000000001','Chassis & Structure',2,7),
  ('11111111-0000-0000-0000-000000000001','Exterior cladding',3,3),
  ('11111111-0000-0000-0000-000000000001','Electrical work',4,4),
  ('11111111-0000-0000-0000-000000000001','Interior & Equipment',5,3),
  ('11111111-0000-0000-0000-000000000001','Paint & Branding',6,2),
  ('11111111-0000-0000-0000-000000000001','Testing & Delivery',7,2);

-- ===== vendors =====
insert into vendors (id, name, category, avg_lead_time_days, reliability_score) values
  ('22222222-0000-0000-0000-000000000001','Sharma Traders','Electronics',4,92),
  ('22222222-0000-0000-0000-000000000002','Metro Steel','Fabrication',6,78),
  ('22222222-0000-0000-0000-000000000003','Kirana Elec','Electricals',3,88),
  ('22222222-0000-0000-0000-000000000004','Delhi Imports','Imported',45,64);

-- ===== item catalog =====
insert into item_catalog (id, name, model, category, default_vendor_id, lead_time_days, buffer_days, serialized) values
  ('33333333-0000-0000-0000-000000000001','Samsung 42" TV','UA42-XYZ','Electronics','22222222-0000-0000-0000-000000000001',3,1,true),
  ('33333333-0000-0000-0000-000000000002','Inverter 2kW',null,'Electricals','22222222-0000-0000-0000-000000000003',3,1,true),
  ('33333333-0000-0000-0000-000000000003','Espresso machine (custom)',null,'Equipment','22222222-0000-0000-0000-000000000004',45,5,true),
  ('33333333-0000-0000-0000-000000000004','Steel sheet 4x8',null,'Fabrication','22222222-0000-0000-0000-000000000002',6,2,false);

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

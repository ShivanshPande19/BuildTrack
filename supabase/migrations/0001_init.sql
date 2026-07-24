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

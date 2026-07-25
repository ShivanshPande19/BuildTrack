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

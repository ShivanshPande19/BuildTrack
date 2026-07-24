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

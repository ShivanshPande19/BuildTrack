-- ============================================================================
-- Migration 0026 — the defects found in the pre-demo audit.
--
-- Runs after 10_workflow_tests.sql, which builds the AZ-200 fixture and defines
-- t_assert / t_expect_error. Each block states the bug it pins down, so a
-- regression says what broke rather than just which line failed.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0026 · a delivery-date change is a full re-plan ==============='

reset role; set test.uid = '';

-- A build whose materials are anchored to a stage in the template BOM.
insert into projects (id, code, name, template_id, pm_id, status, target_delivery_date)
values ('7c000000-0000-0000-0000-0000000000a1','AZ-REPLAN','Replan Build',
        '11111111-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 60);

insert into stages (project_id, template_stage_id, name, ord, status, discipline)
select '7c000000-0000-0000-0000-0000000000a1', ts.id, ts.name, ts.ord, 'todo',
       public.fn_infer_discipline(ts.name)
  from template_stages ts
 where ts.template_id = '11111111-0000-0000-0000-000000000001';

select public.fn_recompute_schedule('7c000000-0000-0000-0000-0000000000a1');

-- The requirement onboarding would generate: anchored on the Electrical stage,
-- which is where 10_workflow_tests put this item in the template BOM.
insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, status)
select '7c000000-0000-0000-0000-0000000000a1','33333333-0000-0000-0000-000000000002', 2,
       s.planned_start, 'pending'
  from stages s
 where s.project_id = '7c000000-0000-0000-0000-0000000000a1' and s.name = 'Electrical work';

select public.fn_recompute_schedule('7c000000-0000-0000-0000-0000000000a1');

select needed_by_date as nb_before, order_by_date as ob_before
  from procurement_requirements
 where project_id = '7c000000-0000-0000-0000-0000000000a1' \gset

-- Push the delivery date out by 30 days and re-plan.
update projects set target_delivery_date = current_date + 90
 where id = '7c000000-0000-0000-0000-0000000000a1';
select public.fn_recompute_schedule('7c000000-0000-0000-0000-0000000000a1', true);

select t_assert(
  (select needed_by_date from procurement_requirements
    where project_id = '7c000000-0000-0000-0000-0000000000a1') = :'nb_before'::date + 30,
  'H1 pushing the delivery date moves each material''s needed-by onto the new plan');

select t_assert(
  (select order_by_date from procurement_requirements
    where project_id = '7c000000-0000-0000-0000-0000000000a1') = :'ob_before'::date + 30,
  'H1 …and its order-by date follows (Hero #1 no longer alerts on the old plan)');

select t_assert(
  (select count(*) from stages
    where project_id = '7c000000-0000-0000-0000-0000000000a1'
      and assigned_due is not null and assigned_due > current_date + 90) = 0,
  'H1 no stage is left due after the new delivery date');

-- A material that is already ordered is history: the re-plan leaves it alone.
insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, status)
values ('7c000000-0000-0000-0000-0000000000a1','33333333-0000-0000-0000-000000000002', 1,
        current_date + 1, 'ordered');
select public.fn_recompute_schedule('7c000000-0000-0000-0000-0000000000a1', true);
select t_assert(
  (select needed_by_date from procurement_requirements
    where project_id = '7c000000-0000-0000-0000-0000000000a1' and status = 'ordered')
    = current_date + 1,
  'H1 an already-ordered material keeps its needed-by (it is a record, not a plan)');

\echo ''
\echo '=== 0026 · re-planning refreshes the build status ================='

-- Past its date → delayed. Pushing the date out must clear that in the same
-- call; it used to need a separate fn_refresh_all_statuses.
update projects set target_delivery_date = current_date - 5
 where id = '7c000000-0000-0000-0000-0000000000a1';
select public.fn_recompute_schedule('7c000000-0000-0000-0000-0000000000a1', true);
select t_assert(
  (select status from projects where id='7c000000-0000-0000-0000-0000000000a1') = 'delayed',
  'H2 a build past its delivery date reads delayed after a re-plan');

update projects set target_delivery_date = current_date + 120
 where id = '7c000000-0000-0000-0000-0000000000a1';
select public.fn_recompute_schedule('7c000000-0000-0000-0000-0000000000a1', true);
select t_assert(
  (select status from projects where id='7c000000-0000-0000-0000-0000000000a1') <> 'delayed',
  'H2 pushing the date out clears delayed immediately, not on the next cron run');

\echo ''
\echo '=== 0026 · a stage cannot be marked done by hand ================='

-- The assignee legitimately has UPDATE on their own stage (for the checklist),
-- and the guard did not cover status / actual_* — so they could approve
-- themselves with a direct write and skip submit + the PM entirely.
reset role; set test.uid = '';
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('7c000000-0000-0000-0000-0000000000a2','AZ-GUARD','Guard Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 30);
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7c000000-0000-0000-0000-0000000000b2','7c000000-0000-0000-0000-0000000000a2',
        'Chassis', 1, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000001');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the assignee
select t_expect_error($$
  update stages set status = 'done'
   where id = '7c000000-0000-0000-0000-0000000000b2'$$,
  'H3 an assignee cannot set their own stage done with a direct UPDATE');

select t_expect_error($$
  update stages set actual_end = current_date
   where id = '7c000000-0000-0000-0000-0000000000b2'$$,
  'H3 …nor backdate actual_end by hand');

-- …but the sanctioned transitions still work for exactly that person.
select public.fn_start_stage('7c000000-0000-0000-0000-0000000000b2');
select t_assert((select status from stages where id='7c000000-0000-0000-0000-0000000000b2') = 'in_progress',
                'H3 Start work still moves the stage (the guard stands aside for the RPC)');

select public.fn_submit_stage('7c000000-0000-0000-0000-0000000000b2') as appr \gset
select t_assert((select count(*) from stage_approvals
                  where stage_id='7c000000-0000-0000-0000-0000000000b2' and status='pending') = 1,
                'H3 Submit for approval still works');

-- the checklist is still the assignee's to tick
reset role; set test.uid = '';
insert into checklist_items (stage_id, label) values
  ('7c000000-0000-0000-0000-0000000000b2','Weld the frame');
set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
update checklist_items set done = true
 where stage_id = '7c000000-0000-0000-0000-0000000000b2';
select t_assert((select done from checklist_items
                  where stage_id='7c000000-0000-0000-0000-0000000000b2') is true,
                'H3 the assignee can still tick their checklist');

-- and the PM's approval still closes it
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select public.fn_decide_stage(:'appr', true);
select t_assert((select status from stages where id='7c000000-0000-0000-0000-0000000000b2') = 'done',
                'H3 the PM''s approval is what marks a stage done');

\echo ''
\echo '=== 0026 · only the right people reopen a ticket ================='

reset role; set test.uid = '';
insert into projects (id, code, name, client_account_id, status, actual_delivery_date, target_delivery_date)
values ('7c000000-0000-0000-0000-0000000000a3','AZ-TKT','Ticket Truck',
        '99999999-0000-0000-0000-000000000001','delivered', current_date - 2, current_date - 2);
insert into tickets (id, ticket_number, project_id, raised_by, category, description, status, resolved_at)
values ('7c000000-0000-0000-0000-0000000000b3','T-900','7c000000-0000-0000-0000-0000000000a3',
        'f0000000-0000-0000-0000-000000000001','equipment','Fridge warm','resolved', now());

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- an unrelated welder
select t_expect_error($$
  select public.fn_reopen_ticket('7c000000-0000-0000-0000-0000000000b3','me too')$$,
  'H4 an unrelated staff member cannot reopen a ticket and force it to high priority');

set test.uid = 'f0000000-0000-0000-0000-000000000001';        -- the client it belongs to
select public.fn_reopen_ticket('7c000000-0000-0000-0000-0000000000b3','Still warm');
select t_assert((select status from tickets where id='7c000000-0000-0000-0000-0000000000b3') = 'in_progress'
            and (select priority from tickets where id='7c000000-0000-0000-0000-0000000000b3') = 'high',
                'H4 the client whose truck it is can reopen it, at high priority');

\echo ''
\echo '=== 0026 · a PO closes all the demand it covers ==================='

-- fn_create_po only parked the ONE requirement passed explicitly, so a PO
-- raised from the blank "New PO" button left its materials pending and the
-- order-by alert kept firing for something already on its way.
reset role; set test.uid = '';
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('7c000000-0000-0000-0000-0000000000a4','AZ-LINK','Link Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 45);
insert into procurement_requirements (project_id, item_catalog_id, qty, needed_by_date, order_by_date, status)
values ('7c000000-0000-0000-0000-0000000000a4','33333333-0000-0000-0000-000000000002', 2,
        current_date + 10, current_date - 1, 'pending'),
       ('7c000000-0000-0000-0000-0000000000a4','33333333-0000-0000-0000-000000000004', 5,
        current_date + 12, current_date + 2, 'pending');

set role authenticated;
set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement
select public.fn_create_po(
  p_vendor  => '22222222-0000-0000-0000-000000000001',
  p_project => '7c000000-0000-0000-0000-0000000000a4',
  p_lines   => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000002','qty',2,'unit_price',1000,'tax_rate',18))
) as polink \gset

select t_assert(
  (select status from procurement_requirements
    where project_id = '7c000000-0000-0000-0000-0000000000a4'
      and item_catalog_id = '33333333-0000-0000-0000-000000000002') = 'ordered',
  'H5 a PO with no explicit requirement still closes the demand its lines cover');

select t_assert(
  (select po_id from procurement_requirements
    where project_id = '7c000000-0000-0000-0000-0000000000a4'
      and item_catalog_id = '33333333-0000-0000-0000-000000000002') = :'polink'::uuid,
  'H5 …and that requirement is linked to the PO that covers it');

select t_assert(
  (select status from procurement_requirements
    where project_id = '7c000000-0000-0000-0000-0000000000a4'
      and item_catalog_id = '33333333-0000-0000-0000-000000000004') = 'pending',
  'H5 a material the PO does NOT cover stays pending (no over-reach)');

\echo ''
\echo '=== 0026 · resubmitting a PO keeps what was not resent ============'

-- notes / ship-to / terms used to be wiped by a null argument, and a vendor or
-- delivery change was dropped entirely when the lines were not resent.
select public.fn_create_po(
  p_vendor        => '22222222-0000-0000-0000-000000000001',
  p_project       => '7c000000-0000-0000-0000-0000000000a4',
  p_notes         => 'Deliver to gate 2',
  p_ship_to       => 'Plant B',
  p_payment_terms => '30 days',
  p_lines         => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',5,'unit_price',200,'tax_rate',18))
) as po2 \gset

set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the build's PM rejects it
select public.fn_reject_po(:'po2', 'Rate is too high');

set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement resubmits
-- Only the vendor changes. No lines, no notes, no terms, no ship-to.
select public.fn_resubmit_po(:'po2', p_vendor => '22222222-0000-0000-0000-000000000002');

select t_assert((select vendor_id from purchase_orders where id = :'po2')
                = '22222222-0000-0000-0000-000000000002',
                'H6 a resubmit that changes only the vendor is not discarded');
select t_assert((select notes from purchase_orders where id = :'po2') = 'Deliver to gate 2'
            and (select ship_to from purchase_orders where id = :'po2') = 'Plant B'
            and (select payment_terms from purchase_orders where id = :'po2') = '30 days',
                'H6 notes / ship-to / terms survive a resubmit that did not resend them');
select t_assert((select approval_status from purchase_orders where id = :'po2') = 'pending_pm'
            and (select pm_signed_by from purchase_orders where id = :'po2') is null,
                'H6 the signatures are still wiped and it re-enters the chain at the PM');

\echo ''
\echo '=== 0026 · receiving a PO twice cannot double the stock =========='

set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the build's PM signs
select public.fn_pm_sign_po(:'po2');
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select public.fn_final_approve_po(:'po2');
set test.uid = 'aa000000-0000-0000-0000-000000000001';
update purchase_orders set status = 'dispatched' where id = :'po2';

reset role; set test.uid = '';
select coalesce((select quantity from stock_items
  where item_catalog_id = '33333333-0000-0000-0000-000000000004'), 0) as qty_before \gset

set role authenticated;
set test.uid = 'aa000000-0000-0000-0000-000000000001';
select public.fn_receive_po(:'po2');
select t_expect_error(format($$select public.fn_receive_po(%L)$$, :'po2'),
  'H7 a second receive of the same PO is refused (stock cannot double)');

reset role; set test.uid = '';
select t_assert((select quantity from stock_items
                  where item_catalog_id = '33333333-0000-0000-0000-000000000004')
                = :'qty_before'::numeric + 5,
                'H7 the bulk quantity landed exactly once');
select t_assert((select count(*) from goods_receipts where po_id = :'po2') = 1,
                'H7 exactly one goods receipt was written');

\echo ''
\echo '=== 0026 · a member owns their name, not their role =============='

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
update profiles set full_name = 'Wasim A. Welder', phone = '+91-99999-00001'
 where id = 'd0000000-0000-0000-0000-000000000001';
select t_assert((select full_name from profiles
                  where id='d0000000-0000-0000-0000-000000000001') = 'Wasim A. Welder',
                'H8 a member can save their own name and phone (Settings → Account details)');

select t_expect_error($$
  update profiles set role = 'admin'
   where id = 'd0000000-0000-0000-0000-000000000001'$$,
  'H8 …but cannot promote themselves');

select t_expect_error($$
  update profiles set email = 'someone@else.co'
   where id = 'd0000000-0000-0000-0000-000000000001'$$,
  'H8 …nor change their own email');

-- RLS hides the row rather than erroring, so this changes nothing (0 rows) —
-- the assertion has to be on the data, not on an exception.
update profiles set full_name = 'Hacked'
 where id = 'b0000000-0000-0000-0000-000000000002';
select t_assert((select full_name from profiles
                  where id='b0000000-0000-0000-0000-000000000002') = 'Rahul PM',
                'H8 …nor edit anyone else''s profile');

\echo ''
\echo '=== 0026 · submitting a design tells the client =================='

reset role; set test.uid = '';
insert into design_artifacts (id, project_id, type, status, created_by)
values ('7c000000-0000-0000-0000-0000000000d1','7c000000-0000-0000-0000-0000000000a3',
        'layout','draft','c0000000-0000-0000-0000-000000000001');
insert into design_versions (artifact_id, version_no, file_url)
values ('7c000000-0000-0000-0000-0000000000d1', 1, 'https://example.test/v1.png');

set role authenticated;
set test.uid = 'c0000000-0000-0000-0000-000000000001';        -- the designer
select public.fn_add_design_version('7c000000-0000-0000-0000-0000000000d1',
  p_image_url => 'https://example.test/v2.png', p_submit => true);

reset role; set test.uid = '';
select t_assert((select count(*) from notifications
                  where user_id = 'f0000000-0000-0000-0000-000000000001'
                    and type = 'design_submitted') >= 1,
                'H9 the client is told when a design is submitted for approval');
select t_assert((select version_no from design_versions
                  where artifact_id='7c000000-0000-0000-0000-0000000000d1'
                  order by version_no desc limit 1) = 2,
                'H9 the new version is numbered atomically');

-- and fn_create_design does the whole thing in one transaction
set role authenticated;
set test.uid = 'c0000000-0000-0000-0000-000000000001';
select public.fn_create_design('7c000000-0000-0000-0000-0000000000a3', 'interior',
  p_image_url => 'https://example.test/int.png', p_submit => true) as art \gset
reset role; set test.uid = '';
select t_assert((select current_version_id from design_artifacts where id = :'art') is not null,
                'H9 a new design always has its first version wired to current_version_id');

\echo ''
\echo '=== 0026 · a fresh database has essentials ======================='

select t_assert((select count(*) from item_catalog where is_essential) > 0,
                'H10 Store''s "request from procurement" picker has something to offer');

\echo ''
\echo '=== 0026 · offboarding never fails on a foreign key ============='

-- Every *nullable* single-column FK to profiles must be ON DELETE SET NULL.
-- A NOT NULL one (notifications.user_id) cascades instead and is skipped by the
-- sweep on purpose — nulling it would violate the column.
select t_assert((select count(*)
                   from pg_constraint con
                   join pg_attribute att
                     on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
                  where con.contype = 'f'
                    and con.confrelid = 'public.profiles'::regclass
                    and con.confdeltype = 'a'
                    and array_length(con.conkey, 1) = 1
                    and not att.attnotnull) = 0,
                'H11 every nullable FK to profiles has ON DELETE SET NULL');

\echo ''
\echo '=== 0026 · a PM hand-over carries the work in flight ============='

-- approver_id and purchase_orders.pm_id are snapshots: reassigning a build used
-- to leave both pointing at the old PM, so the new PM's queue was empty while
-- the team waited and the PO could not be signed by anyone.
reset role; set test.uid = '';
insert into auth.users (id, email) values
  ('b0000000-0000-0000-0000-000000000003','pm3@az.co') on conflict do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('b0000000-0000-0000-0000-000000000003','Neha PM','pm3@az.co','pm','active')
  on conflict do nothing;

insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('7c000000-0000-0000-0000-0000000000a5','AZ-HAND','Handover Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 40);
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7c000000-0000-0000-0000-0000000000b5','7c000000-0000-0000-0000-0000000000a5',
        'Cladding', 1, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000002');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000002';        -- the assignee submits
select public.fn_submit_stage('7c000000-0000-0000-0000-0000000000b5');

set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement raises a PO
select public.fn_create_po(
  p_vendor  => '22222222-0000-0000-0000-000000000001',
  p_project => '7c000000-0000-0000-0000-0000000000a5',
  p_lines   => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',1,'unit_price',100,'tax_rate',18))
) as pohand \gset

-- hand the build to a different PM
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
select public.fn_assign_pm('7c000000-0000-0000-0000-0000000000a5',
                           'b0000000-0000-0000-0000-000000000003');

reset role; set test.uid = '';
select t_assert((select approver_id from stage_approvals
                  where stage_id = '7c000000-0000-0000-0000-0000000000b5' and status = 'pending')
                = 'b0000000-0000-0000-0000-000000000003',
                'H12 a pending stage approval moves to the new PM');
select t_assert((select pm_id from purchase_orders where id = :'pohand')
                = 'b0000000-0000-0000-0000-000000000003',
                'H12 an unsigned PO moves to the new PM');

-- …and the new PM can actually act on both
set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000003';
select public.fn_pm_sign_po(:'pohand');
select t_assert((select approval_status from purchase_orders where id = :'pohand') = 'pending_final',
                'H12 the new PM can sign the PO they inherited');

\echo ''
\echo '=== 0026 · a disabled account can read nothing =================='

-- status was shown on the Team screen but enforced nowhere: my_role() returned
-- the role regardless, so is_staff()/has_role()/is_admin() all said yes.
reset role; set test.uid = '';
insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000009','gone@az.co') on conflict do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('d0000000-0000-0000-0000-000000000009','Gone Guy','gone@az.co','workshop','disabled')
  on conflict do nothing;

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000009';
select t_assert(public.my_role() is null,
                'H13 a disabled account has no role');
select t_assert(public.is_staff() = false and public.is_admin() = false,
                'H13 …so it is neither staff nor admin (is_admin is false, not NULL)');
select t_assert((select count(*) from projects) = 0,
                'H13 …and RLS shows it no builds at all');

-- an active member of the same role is unaffected
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_assert(public.is_staff() = true and (select count(*) from projects) > 0,
                'H13 an active member of the same role still sees the builds');

-- a disabled admin cannot slip past the `if not is_admin()` guards either
reset role; set test.uid = '';
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000009','exadmin@az.co') on conflict do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('a0000000-0000-0000-0000-000000000009','Ex Admin','exadmin@az.co','admin','disabled')
  on conflict do nothing;
set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000009';
select t_expect_error($$
  select public.fn_assign_pm('7c000000-0000-0000-0000-0000000000a5',
                             'b0000000-0000-0000-0000-000000000002')$$,
  'H13 a disabled admin is refused by the RPC guards');

-- The same hole, from the other side: a caller with no profile at all. These
-- functions are SECURITY DEFINER and granted to PUBLIC, so `if not
-- public.is_admin()` being skipped for a NULL role meant an anonymous POST to
-- /rpc/fn_assign_pm could reassign a build.
set test.uid = '00000000-0000-0000-0000-0000000000ff';         -- no profile row
select t_assert(public.my_role() is null and public.is_admin() = false,
                'H13 a caller with no profile is not an admin (is_admin is false, not NULL)');
select t_expect_error($$
  select public.fn_assign_pm('7c000000-0000-0000-0000-0000000000a5',
                             'b0000000-0000-0000-0000-000000000002')$$,
  'H13 …and is refused, instead of slipping past a guard that never fired');

reset role;
\echo ''
\echo '=== 0026 HARDENING TESTS PASSED =================================='

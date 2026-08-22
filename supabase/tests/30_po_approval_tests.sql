-- ============================================================================
-- Purchase Order approval chain (migration 0020), run as real (non-superuser)
-- users so RLS + the guard trigger actually apply.
--
--   Procurement raises  →  PM signs (project PO)  →  Admin finally approves
--                          general PO skips the PM and goes straight to Admin
--
-- Reuses the AZ-200 fixture from 10_workflow_tests.sql. That suite deletes pm1
-- and nulls AZ-200's PM at the end, so we (re)assign an active PM here first.
-- t_assert / t_expect_error are defined in 10_workflow_tests.sql.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== PO approval · setup ==========================================='

-- extra people this suite needs (workflow suite has no procurement role)
reset role; set test.uid = '';
insert into auth.users (id, email) values
  ('aa000000-0000-0000-0000-000000000001','proc@az.co'),
  ('b0000000-0000-0000-0000-000000000003','pm3@az.co')
on conflict (id) do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('aa000000-0000-0000-0000-000000000001','Prakash Procure','proc@az.co','procurement','active'),
  ('b0000000-0000-0000-0000-000000000003','Neha PM','pm3@az.co','pm','active')
on conflict (id) do nothing;

-- give AZ-200 an active PM again (pm2 is still active)
select public.fn_assign_pm('77777777-0000-0000-0000-000000000001',
                           'b0000000-0000-0000-0000-000000000002');

-- the requirement AZ-200's onboarding auto-generated (item 33333333-…-2)
select id as reqid from procurement_requirements
 where project_id = '77777777-0000-0000-0000-000000000001' limit 1 \gset

\echo ''
\echo '=== A · only procurement/admin can raise a PO ====================='

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- a welder
select t_expect_error($$
  select public.fn_create_po(p_vendor => '22222222-0000-0000-0000-000000000001')$$,
  'PO1 workshop staff cannot raise a purchase order');

-- direct INSERT is now blocked too — a PO must go through fn_create_po
set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement
select t_expect_error($$
  insert into purchase_orders (po_number, status) values ('PO-RAW', 'ordered')$$,
  'PO1 even procurement cannot insert a PO directly (must use fn_create_po)');

\echo ''
\echo '=== B · procurement raises a project PO → pending_pm =============='

select public.fn_create_po(
  p_vendor      => '22222222-0000-0000-0000-000000000001',
  p_project     => '77777777-0000-0000-0000-000000000001',
  p_requirement => :'reqid',
  p_lines       => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000002','qty',2,'unit_price',1000,'tax_rate',18),
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',3,'unit_price',500,'tax_rate',18))
) as po1 \gset

select t_assert((select approval_status from purchase_orders where id = :'po1') = 'pending_pm',
                'PO2 a project PO starts awaiting the PM''s signature');
select t_assert((select pm_id from purchase_orders where id = :'po1')
                = 'b0000000-0000-0000-0000-000000000002',
                'PO2 the PO is routed to the build''s PM');
select t_assert((select subtotal from purchase_orders where id = :'po1') = 3500
            and (select tax_total from purchase_orders where id = :'po1') = 630
            and (select amount   from purchase_orders where id = :'po1') = 4130,
                'PO2 totals are computed from the lines (3500 + 18% = 4130)');
select t_assert((select status from procurement_requirements where id = :'reqid') = 'ordered',
                'PO2 the requirement it fulfils leaves the To-Order list');
select t_assert((select count(*) from po_approval_events where po_id = :'po1' and event = 'created') = 1,
                'PO2 a "created" approval event is on the record');
reset role;
select t_assert((select count(*) from notifications
                  where user_id = 'b0000000-0000-0000-0000-000000000002' and type = 'po_approval') >= 1,
                'PO2 the PM is notified there is a PO to sign');
set role authenticated;

\echo ''
\echo '=== C · a PO cannot be dispatched/received before approval ========'

set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement
select t_expect_error(format($$update purchase_orders set status = 'dispatched' where id = %L$$, :'po1'),
  'PO3 an unapproved PO cannot be dispatched (guard trigger)');

\echo ''
\echo '=== D · signing: right people, right order ========================'

-- a PM who does not own the build cannot sign
set test.uid = 'b0000000-0000-0000-0000-000000000003';        -- the other PM
select t_expect_error(format($$select public.fn_pm_sign_po(%L)$$, :'po1'),
  'PO4 a PM who does not own the build cannot sign its PO');

-- final approval is not available until the PM has signed
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
select t_expect_error(format($$select public.fn_final_approve_po(%L)$$, :'po1'),
  'PO4 final approval is refused while the PM has not signed');

-- the build's PM signs → moves to final approval
set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the build's PM
select public.fn_pm_sign_po(:'po1', 'Quantities look right.');
select t_assert((select approval_status from purchase_orders where id = :'po1') = 'pending_final',
                'PO4 the PM''s signature moves it to final approval');
select t_assert((select pm_signed_by from purchase_orders where id = :'po1')
                = 'b0000000-0000-0000-0000-000000000002',
                'PO4 the PM''s signature is attributed');

-- procurement (not an owner) cannot give final approval
set test.uid = 'aa000000-0000-0000-0000-000000000001';
select t_expect_error(format($$select public.fn_final_approve_po(%L)$$, :'po1'),
  'PO5 only an admin/owner can give final approval');

-- admin gives final approval → the order is placed
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select public.fn_final_approve_po(:'po1', 'Approved.');
select t_assert((select approval_status from purchase_orders where id = :'po1') = 'approved',
                'PO5 final approval marks the PO approved');
select t_assert((select final_signed_by from purchase_orders where id = :'po1')
                = 'a0000000-0000-0000-0000-000000000001',
                'PO5 the final signature is attributed');
select t_assert((select count(*) from po_approval_events where po_id = :'po1') = 3,
                'PO5 the full trail is three events (created → pm_signed → final_signed)');
reset role;
select t_assert((select count(*) from notifications
                  where user_id = 'aa000000-0000-0000-0000-000000000001' and type = 'po_approved') >= 1,
                'PO5 whoever raised the PO is told the order is live');
set role authenticated;

\echo ''
\echo '=== E · once approved, it can move through fulfilment =============='

set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement
update purchase_orders set status = 'dispatched', expected_date = current_date + 5 where id = :'po1';
select t_assert((select status from purchase_orders where id = :'po1') = 'dispatched',
                'PO6 an approved PO can now be dispatched');

\echo ''
\echo '=== F · general (stock) PO skips the PM ==========================='

select public.fn_create_po(
  p_vendor => '22222222-0000-0000-0000-000000000003',
  p_lines  => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',10,'unit_price',450,'tax_rate',18))
) as po2 \gset

select t_assert((select approval_status from purchase_orders where id = :'po2') = 'pending_final',
                'PO7 a general PO (no project) goes straight to final approval');
select t_assert((select pm_id from purchase_orders where id = :'po2') is null,
                'PO7 a general PO has no PM to sign');

\echo ''
\echo '=== G · rejection is a rework loop, not a dead end ================'

set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement
select public.fn_create_po(
  p_vendor      => '22222222-0000-0000-0000-000000000001',
  p_project     => '77777777-0000-0000-0000-000000000001',
  p_requirement => :'reqid',
  p_lines       => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000002','qty',1,'unit_price',1200,'tax_rate',18))
) as po3 \gset

select t_assert((select status from procurement_requirements where id = :'reqid') = 'ordered',
                'PO8 raising the PO parks the requirement');

-- a reason is mandatory
set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the build's PM
select t_expect_error(format($$select public.fn_reject_po(%L, '')$$, :'po3'),
  'PO8 a rejection needs a reason');

-- PM sends it back with a remark
select public.fn_reject_po(:'po3', 'Vendor quote is too high — get a second one.');
select t_assert((select approval_status from purchase_orders where id = :'po3') = 'rejected',
                'PO8 the PM sends the PO back');
select t_assert((select status from procurement_requirements where id = :'reqid') = 'ordered',
                'PO8 the requirement stays parked — the PO is being reworked, not abandoned');
reset role;
select t_assert((select count(*) from notifications
                  where user_id = 'aa000000-0000-0000-0000-000000000001' and type = 'po_rejected') >= 1,
                'PO8 procurement is told what to fix');
set role authenticated;

-- a rejected PO can't jump straight to approved
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select t_expect_error(format($$select public.fn_final_approve_po(%L)$$, :'po3'),
  'PO8 a rejected PO cannot be approved without a resubmit');

-- procurement fixes the price and resubmits → back to the PM
set test.uid = 'aa000000-0000-0000-0000-000000000001';
select public.fn_resubmit_po(:'po3',
  p_vendor => '22222222-0000-0000-0000-000000000002',
  p_lines  => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000002','qty',1,'unit_price',900,'tax_rate',18)));
select t_assert((select approval_status from purchase_orders where id = :'po3') = 'pending_pm',
                'PO9 resubmitting a project PO sends it back to the PM');
select t_assert((select pm_signed_at from purchase_orders where id = :'po3') is null
            and (select rejection_reason from purchase_orders where id = :'po3') is null,
                'PO9 the old signature + rejection are wiped on resubmit');
select t_assert((select amount from purchase_orders where id = :'po3') = 1062,
                'PO9 the revised price recomputes the total (900 + 18% = 1062)');
select t_assert((select count(*) from po_approval_events where po_id = :'po3' and event = 'resubmitted') = 1,
                'PO9 the resubmit is on the record');

-- PM signs the revision, admin rejects it → both procurement AND the PM hear about it
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select public.fn_pm_sign_po(:'po3');
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select public.fn_reject_po(:'po3', 'Hold this until next quarter.');
reset role;
select t_assert((select count(*) from notifications
                  where user_id = 'aa000000-0000-0000-0000-000000000001' and type = 'po_rejected') >= 2,
                'PO10 procurement is told when the owner rejects');
select t_assert((select count(*) from notifications
                  where user_id = 'b0000000-0000-0000-0000-000000000002' and type = 'po_rejected') >= 1,
                'PO10 the PM is kept in the loop when the owner overrules their signature');
set role authenticated;

\echo ''
\echo '=== H · costs stay off the shop floor ============================='

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- a welder
select t_assert((select count(*) from purchase_orders) = 0,
                'PO9 workshop cannot read purchase orders / their costs at all');

reset role;
\echo ''
\echo '=== PO APPROVAL TESTS PASSED ======================================'

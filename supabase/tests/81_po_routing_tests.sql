-- ============================================================================
-- Migration 0027 — a purchase order on a PM-less build is refused, not quietly
-- re-routed past the PM's signature.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the AZ-200
-- fixture) and 30_po_approval_tests.sql (the procurement user).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0027 · a project PO needs the build to have a PM ============='

reset role; set test.uid = '';

-- A build with a PM, and the same build after the PM is offboarded. Offboarding
-- is the real path into this state: projects.pm_id is ON DELETE SET NULL (0009)
-- so that removing a person can never fail on a foreign key.
insert into auth.users (id, email) values
  ('b0000000-0000-0000-0000-00000000000f','pmgone@az.co') on conflict do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('b0000000-0000-0000-0000-00000000000f','Temp PM','pmgone@az.co','pm','active')
  on conflict do nothing;

insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('7d000000-0000-0000-0000-0000000000a1','AZ-NOPM','Orphan Build',
        'b0000000-0000-0000-0000-00000000000f','on_track', current_date + 30);

-- While the PM is there, a project PO routes to them. (The control case: if
-- this stopped working the refusal below would pass for the wrong reason.)
set role authenticated;
set test.uid = 'aa000000-0000-0000-0000-000000000001';        -- procurement
select public.fn_create_po(
  p_vendor  => '22222222-0000-0000-0000-000000000001',
  p_project => '7d000000-0000-0000-0000-0000000000a1',
  p_lines   => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',1,'unit_price',100,'tax_rate',18))
) as po_withpm \gset

select t_assert((select approval_status from purchase_orders where id = :'po_withpm') = 'pending_pm',
                'R1 with a PM in place, a project PO still routes to them first');

-- Now offboard the PM. The build keeps running; its pm_id goes null.
reset role; set test.uid = '';
delete from auth.users where id = 'b0000000-0000-0000-0000-00000000000f';
select t_assert((select pm_id from projects where id='7d000000-0000-0000-0000-0000000000a1') is null,
                'R2 offboarding the PM leaves the build without one (ON DELETE SET NULL)');

set role authenticated;
set test.uid = 'aa000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_create_po(
    p_vendor  => '22222222-0000-0000-0000-000000000001',
    p_project => '7d000000-0000-0000-0000-0000000000a1',
    p_lines   => jsonb_build_array(
      jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',1,'unit_price',100,'tax_rate',18)))$$,
  'R2 a PO on a PM-less build is refused, not routed straight to the owner');

-- …and nothing was written on the way out.
reset role; set test.uid = '';
select t_assert((select count(*) from purchase_orders
                  where project_id = '7d000000-0000-0000-0000-0000000000a1') = 1,
                'R2 the refused PO left no half-written row behind');

\echo ''
\echo '=== 0027 · a general PO is unaffected ============================'

-- The rule is about *project* POs. A stock order has no build and no PM by
-- design, and must still go straight to the owner.
set role authenticated;
set test.uid = 'aa000000-0000-0000-0000-000000000001';
select public.fn_create_po(
  p_vendor => '22222222-0000-0000-0000-000000000002',
  p_lines  => jsonb_build_array(
    jsonb_build_object('item_catalog_id','33333333-0000-0000-0000-000000000004','qty',10,'unit_price',200,'tax_rate',18))
) as po_general \gset

select t_assert((select approval_status from purchase_orders where id = :'po_general') = 'pending_final',
                'R3 a general stock PO still skips the PM and goes to the owner');
select t_assert((select pm_id from purchase_orders where id = :'po_general') is null,
                'R3 …and carries no PM at all');

\echo ''
\echo '=== 0027 · a nonexistent build is refused ========================'

select t_expect_error($$
  select public.fn_create_po(
    p_project => '7d000000-0000-0000-0000-0000000000ff',
    p_lines   => '[]'::jsonb)$$,
  'R4 a PO against a build that does not exist is refused');

\echo ''
\echo '=== 0027 · resubmit closes the same hole ========================='

-- The PO raised while the PM existed is now rejected and resubmitted — the way
-- back round routed past the missing PM too.
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin rejects
select public.fn_reject_po(:'po_withpm', 'Wrong vendor');

set test.uid = 'aa000000-0000-0000-0000-000000000001';
select t_expect_error(format($$select public.fn_resubmit_po(%L)$$, :'po_withpm'),
  'R5 resubmitting onto a PM-less build is refused for the same reason');

select t_assert((select approval_status from purchase_orders where id = :'po_withpm') = 'rejected',
                'R5 the PO stays rejected rather than half-resubmitted');

-- Give the build a PM again and the same resubmit goes through, back to them.
reset role; set test.uid = '';
set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select public.fn_assign_pm('7d000000-0000-0000-0000-0000000000a1',
                           'b0000000-0000-0000-0000-000000000002');

set test.uid = 'aa000000-0000-0000-0000-000000000001';
select public.fn_resubmit_po(:'po_withpm');
select t_assert((select approval_status from purchase_orders where id = :'po_withpm') = 'pending_pm',
                'R5 once a PM is assigned, the resubmit routes to them');
select t_assert((select pm_id from purchase_orders where id = :'po_withpm')
                = 'b0000000-0000-0000-0000-000000000002',
                'R5 …and the PO is addressed to the new PM');

reset role;
\echo ''
\echo '=== 0027 PO ROUTING TESTS PASSED ================================='

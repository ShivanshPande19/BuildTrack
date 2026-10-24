-- ============================================================================
-- Migration 0036 — the fitter records the part they fit; a client's request is
-- about their own truck; a visit is told in India time.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the users) and
-- 20_service_tests.sql (the technician 50…02). Builds its own fixtures.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0036 · whoever holds work on the stage fits the part ========='

reset role; set test.uid = '';

-- A build with no client: a supervisor (welder) holds the Workshop stage and
-- has given one work item to welder2. Handover has nobody on it yet.
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('b4000000-0000-0000-0000-0000000000a1','AZ-FIT','Fitting Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 40);

insert into stages (id, project_id, name, ord, status, discipline, assignee_id) values
  ('b4000000-0000-0000-0000-0000000000b1','b4000000-0000-0000-0000-0000000000a1',
   'Workshop', 1, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000001'),
  ('b4000000-0000-0000-0000-0000000000b2','b4000000-0000-0000-0000-0000000000a1',
   'Handover', 2, 'todo', null, null);

insert into stage_tasks (id, stage_id, title, ord, assignee_id) values
  ('b4000000-0000-0000-0000-0000000000c1','b4000000-0000-0000-0000-0000000000b1',
   'Equipment fittings', 1, 'd0000000-0000-0000-0000-000000000002');

insert into component_instances (id, item_catalog_id, serial_number, status) values
  ('b4000000-0000-0000-0000-0000000000f1','33333333-0000-0000-0000-000000000004','SN-FIT-1','in_stock'),
  ('b4000000-0000-0000-0000-0000000000f2','33333333-0000-0000-0000-000000000004','SN-FIT-2','in_stock'),
  ('b4000000-0000-0000-0000-0000000000f3','33333333-0000-0000-0000-000000000004','SN-FIT-3','in_stock');

set role authenticated;

set test.uid = 'd0000000-0000-0000-0000-000000000002';        -- welder2, holds a work item
select public.fn_install_component('b4000000-0000-0000-0000-0000000000f1',
                                   'b4000000-0000-0000-0000-0000000000b1');
select t_assert((select status = 'installed'
                        and installed_stage_id = 'b4000000-0000-0000-0000-0000000000b1'
                        and installed_by = 'd0000000-0000-0000-0000-000000000002'
                   from component_instances where id = 'b4000000-0000-0000-0000-0000000000f1'),
                'I1 a worker with a work item on the stage can fit a part into it');

select t_expect_error($$
  select public.fn_install_component('b4000000-0000-0000-0000-0000000000f2',
                                     'b4000000-0000-0000-0000-0000000000b2')$$,
  'I2 …but not into a stage of the same build they have no work on');

set test.uid = 'c0000000-0000-0000-0000-000000000001';        -- the designer, no work here
select t_expect_error($$
  select public.fn_install_component('b4000000-0000-0000-0000-0000000000f2',
                                     'b4000000-0000-0000-0000-0000000000b1')$$,
  'I3 someone with no work on the stage cannot fit a part into it');

-- Handover has no assignee. The old check came out NULL there and let anyone
-- through.
select t_expect_error($$
  select public.fn_install_component('b4000000-0000-0000-0000-0000000000f2',
                                     'b4000000-0000-0000-0000-0000000000b2')$$,
  'I4 a stage with nobody on it is not open to everyone');
select t_assert((select status from component_instances
                  where id = 'b4000000-0000-0000-0000-0000000000f2') = 'in_stock',
                'I4 …and the part is still in stock');

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the supervisor
select public.fn_install_component('b4000000-0000-0000-0000-0000000000f2',
                                   'b4000000-0000-0000-0000-0000000000b1');
select t_assert((select status from component_instances
                  where id = 'b4000000-0000-0000-0000-0000000000f2') = 'installed',
                'I5 the stage''s own assignee still can');

set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
select public.fn_install_component('b4000000-0000-0000-0000-0000000000f3',
                                   'b4000000-0000-0000-0000-0000000000b2');
select t_assert((select status from component_instances
                  where id = 'b4000000-0000-0000-0000-0000000000f3') = 'installed',
                'I6 an admin still can, on any open stage');


\echo ''
\echo '=== 0036 · a client raises a request on their own truck =========='

reset role; set test.uid = '';
insert into projects (id, code, name, client_account_id, status, actual_delivery_date, target_delivery_date)
values ('b4000000-0000-0000-0000-0000000000a2','AZ-SVC','Service Truck',
        '99999999-0000-0000-0000-000000000001','delivered', current_date - 5, current_date - 5);
set role authenticated;

set test.uid = 'f0000000-0000-0000-0000-000000000001';        -- the client
insert into tickets (project_id, category, description, priority, status)
values ('b4000000-0000-0000-0000-0000000000a2','electrical','Breaker trips','medium','open');
select t_assert((select count(*) from tickets
                  where project_id = 'b4000000-0000-0000-0000-0000000000a2') = 1,
                'K1 a client raises a request on their own truck, the way the app sends it');

select t_expect_error($$
  insert into tickets (project_id, category, description)
  values ('b4000000-0000-0000-0000-0000000000a1','other','Not my truck')$$,
  'K2 …but not on a build that is not theirs');

select t_expect_error($$
  insert into tickets (project_id, category, description, status, resolution_type, resolution_note, resolved_at)
  values ('b4000000-0000-0000-0000-0000000000a2','other','Already sorted','resolved',
          'repair','Done', now())$$,
  'K3 …nor insert one already resolved');

select t_expect_error($$
  insert into tickets (project_id, category, description, assigned_to)
  values ('b4000000-0000-0000-0000-0000000000a2','other','Send Arjun',
          '50000000-0000-0000-0000-000000000002')$$,
  'K4 …nor pick the technician themselves');


\echo ''
\echo '=== 0036 · a visit is told in India time ========================='

set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin books it
select public.fn_schedule_visit(
  (select id from tickets where project_id = 'b4000000-0000-0000-0000-0000000000a2'),
  '50000000-0000-0000-0000-000000000002', '2026-10-26 05:30:00+00');

reset role; set test.uid = '';
select t_assert((select body from notifications
                  where user_id = 'f0000000-0000-0000-0000-000000000001' and type = 'visit'
                  order by created_at desc limit 1) like '% on 26 Oct at 11:00 AM.',
                'V1 05:30 UTC reaches the client as 11:00 AM');
select t_assert((select body from notifications
                  where user_id = '50000000-0000-0000-0000-000000000002' and type = 'visit'
                  order by created_at desc limit 1) like 'You are scheduled for 26 Oct, 11:00 AM on %',
                'V2 …and the technician as the same hour');


\echo ''
\echo '=== 0036 · a delivered truck is not on the To Order list =========='

insert into procurement_requirements (project_id, item_catalog_id, qty, status, order_by_date) values
  ('b4000000-0000-0000-0000-0000000000a2','33333333-0000-0000-0000-000000000004', 1, 'pending', current_date),
  ('b4000000-0000-0000-0000-0000000000a1','33333333-0000-0000-0000-000000000004', 1, 'pending', current_date);

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select t_assert((select count(*) from v_order_due
                  where project_id = 'b4000000-0000-0000-0000-0000000000a2') = 0,
                'O1 a pending requirement on a delivered build is not offered to order');
select t_assert((select count(*) from v_order_due
                  where project_id = 'b4000000-0000-0000-0000-0000000000a1') = 1,
                'O2 …while one on a build still in progress is');
reset role; set test.uid = '';
\echo ''
\echo '=== 0036 FITTER / CLIENT TICKET TESTS PASSED ======================'

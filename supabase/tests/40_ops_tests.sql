-- ============================================================================
-- Ops command center (migration 0021): sub-teams, PO priority, factory board.
-- Reuses the AZ-200 fixture + the procurement/admin users from earlier suites.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== OPS · sub-teams ==============================================='

reset role;
select t_assert((select count(*) from sub_teams where role = 'workshop') = 4,
                'ST1 Workshop seeds its four teams (Welding/Paint/Electrical/Fitter)');

-- admin can assign a person to a team; a non-admin cannot create teams
set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';                 -- admin
update profiles set sub_team_id = (select id from sub_teams where role='workshop' and name='Welding')
 where id = 'd0000000-0000-0000-0000-000000000001';
select t_assert((select st.name from profiles p join sub_teams st on st.id = p.sub_team_id
                  where p.id = 'd0000000-0000-0000-0000-000000000001') = 'Welding',
                'ST2 a member can be placed in a sub-team');

set test.uid = 'aa000000-0000-0000-0000-000000000001';                 -- procurement (not admin)
select t_expect_error($$insert into sub_teams (role, name) values ('workshop','Rogue')$$,
  'ST3 only an admin can create a sub-team');
select t_assert((select count(*) from sub_teams) >= 4,
                'ST3 any staff member can still read the team list');

\echo ''
\echo '=== OPS · PO approval priority (deterministic) ===================='

-- three POs awaiting final approval, with controlled order-by dates
reset role; set test.uid = '';
insert into purchase_orders (po_number, status, approval_status, needed_by, submitted_at) values
  ('PO-PRI-CRIT','ordered','pending_final', current_date - 2,  now()),
  ('PO-PRI-HIGH','ordered','pending_final', current_date + 2,  now()),
  ('PO-PRI-MED', 'ordered','pending_final', current_date + 6,  now()),
  ('PO-PRI-LOW', 'ordered','pending_final', current_date + 30, now()),
  ('PO-PRI-NONE','ordered','pending_final', null,              now());

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';                 -- admin reads the queue
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-CRIT') = 'critical',
                'PR1 an overdue order-by is CRITICAL');
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-HIGH') = 'high',
                'PR1 within 3 days is HIGH');
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-MED') = 'medium',
                'PR1 within 7 days is MEDIUM');
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-LOW') = 'low',
                'PR1 later than a week is LOW');
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-NONE') = 'medium',
                'PR1 a general PO with no order-by defaults to MEDIUM');

-- the critical one must rank ahead of the low one
select t_assert(
  (select priority_rank from v_po_pending_approvals where po_number='PO-PRI-CRIT')
  < (select priority_rank from v_po_pending_approvals where po_number='PO-PRI-LOW'),
  'PR2 critical outranks low in the queue');

\echo ''
\echo '=== OPS · admin priority override ================================='

set test.uid = 'aa000000-0000-0000-0000-000000000001';                 -- procurement
select t_expect_error(
  $$select public.fn_set_po_priority((select id from purchase_orders where po_number='PO-PRI-LOW'), 'critical')$$,
  'PR3 procurement cannot change a PO''s priority');

set test.uid = 'a0000000-0000-0000-0000-000000000001';                 -- admin
select public.fn_set_po_priority(
  (select id from purchase_orders where po_number='PO-PRI-LOW'), 'critical');
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-LOW') = 'critical',
                'PR3 an admin override wins over the auto rule');
-- clearing it falls back to the derived value
select public.fn_set_po_priority(
  (select id from purchase_orders where po_number='PO-PRI-LOW'), null);
select t_assert((select priority from v_po_pending_approvals where po_number='PO-PRI-LOW') = 'low',
                'PR3 clearing the override falls back to the derived priority');

\echo ''
\echo '=== OPS · factory board =========================================='

-- a controlled, active build: current stage in progress, assigned to the welder
-- (who we placed in the Welding team above).
reset role; set test.uid = '';
insert into projects (id, code, name, status, progress_pct)
values ('7a000000-0000-0000-0000-0000000000aa','AZ-OPS','Ops Board Test','at_risk', 40);
insert into stages (id, project_id, name, ord, status, discipline, assignee_id, actual_start)
values ('7a000000-0000-0000-0000-0000000000b1','7a000000-0000-0000-0000-0000000000aa',
        'Chassis & Structure', 1, 'in_progress', 'workshop',
        'd0000000-0000-0000-0000-000000000001', current_date - 2);
update projects set current_stage_id = '7a000000-0000-0000-0000-0000000000b1'
 where id = '7a000000-0000-0000-0000-0000000000aa';

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';                 -- admin
select t_assert((select count(*) from v_ops_board where code = 'AZ-OPS') = 1,
                'OB1 an active build shows on the factory board');
select t_assert((select current_stage_name from v_ops_board where code = 'AZ-OPS') = 'Chassis & Structure'
            and (select current_discipline from v_ops_board where code = 'AZ-OPS') = 'workshop',
                'OB2 the board knows the current stage + the department on it');
select t_assert((select assignee_name from v_ops_board where code = 'AZ-OPS') = 'Wasim Welder'
            and (select sub_team_name from v_ops_board where code = 'AZ-OPS') = 'Welding',
                'OB3 the board knows who is on it and their sub-team');
select t_assert((select days_in_stage from v_ops_board where code = 'AZ-OPS') = 2,
                'OB4 the board shows how long the build has sat in this stage');
select t_assert((select count(*) from v_ops_board where code = 'AZ-200') = 0,
                'OB5 a delivered build drops off the active board');

reset role;
\echo ''
\echo '=== OPS TESTS PASSED =============================================='

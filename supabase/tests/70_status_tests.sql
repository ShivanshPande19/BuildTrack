-- ============================================================================
-- Build status vs the promised delivery date (migration 0024).
-- The bug: a build past its target_delivery_date still read "on track".
-- t_assert from 10_workflow_tests.sql.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== STATUS · delivery date drives delayed / at-risk =============='

reset role; set test.uid = '';

-- 1) past the promised delivery, not delivered, work still open → DELAYED
insert into projects (id, code, name, status, target_delivery_date)
values ('7b000000-0000-0000-0000-0000000000c1','AZ-LATE','Late Build','on_track', current_date - 5);
insert into stages (project_id, name, ord, status)
values ('7b000000-0000-0000-0000-0000000000c1','Assembly', 1, 'in_progress');
select public.fn_recompute_status('7b000000-0000-0000-0000-0000000000c1');
select t_assert((select status from projects where id='7b000000-0000-0000-0000-0000000000c1') = 'delayed',
                'SD1 a build past its delivery date is delayed (was the bug)');

-- 2) delivery within a week, work still open → AT_RISK
insert into projects (id, code, name, status, target_delivery_date)
values ('7b000000-0000-0000-0000-0000000000c2','AZ-SOON','Due Soon','on_track', current_date + 3);
insert into stages (project_id, name, ord, status)
values ('7b000000-0000-0000-0000-0000000000c2','Fitout', 1, 'in_progress');
select public.fn_recompute_status('7b000000-0000-0000-0000-0000000000c2');
select t_assert((select status from projects where id='7b000000-0000-0000-0000-0000000000c2') = 'at_risk',
                'SD2 delivery within a week with work left is at-risk');

-- 3) plenty of time, nothing overdue → ON_TRACK (and it flips back from delayed)
insert into projects (id, code, name, status, target_delivery_date)
values ('7b000000-0000-0000-0000-0000000000c3','AZ-OK','Comfortable','delayed', current_date + 90);
insert into stages (project_id, name, ord, status)
values ('7b000000-0000-0000-0000-0000000000c3','Design', 1, 'todo');
select public.fn_recompute_status('7b000000-0000-0000-0000-0000000000c3');
select t_assert((select status from projects where id='7b000000-0000-0000-0000-0000000000c3') = 'on_track',
                'SD3 plenty of time and nothing overdue recomputes to on-track');

-- 4) a delivered build ignores the dates entirely → DELIVERED
insert into projects (id, code, name, status, target_delivery_date, actual_delivery_date)
values ('7b000000-0000-0000-0000-0000000000c4','AZ-DONE','Handed Over','on_track', current_date - 10, current_date - 5);
select public.fn_recompute_status('7b000000-0000-0000-0000-0000000000c4');
select t_assert((select status from projects where id='7b000000-0000-0000-0000-0000000000c4') = 'delivered',
                'SD4 a delivered build stays delivered regardless of dates');

reset role;
\echo ''
\echo '=== STATUS TESTS PASSED ==========================================='

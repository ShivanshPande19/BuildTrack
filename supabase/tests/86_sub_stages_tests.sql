-- ============================================================================
-- Migration 0033 — a workshop stage breaks into sub-stages: the supervisor's
-- plan, the worker's job, and the same step rule 0031 gave stages.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0033 · the supervisor breaks the stage down =================='

reset role; set test.uid = '';

-- d1 supervises; d2 is one of their people. (0032 marks the supervisor; this
-- suite only needs the two to be different workshop members.)
update profiles set is_supervisor = true
 where id = 'd0000000-0000-0000-0000-000000000001';

insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('a1000000-0000-0000-0000-0000000000a1','AZ-SUB','Sub Stage Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 60);

-- One workshop stage, handed to the supervisor.
insert into stages (id, project_id, name, ord, step, status, discipline, assignee_id)
values ('a1000000-0000-0000-0000-0000000000b1','a1000000-0000-0000-0000-0000000000a1',
        'Workshop', 1, 1, 'in_progress', 'workshop',
        'd0000000-0000-0000-0000-000000000001');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the supervisor

insert into stage_tasks (id, stage_id, title, ord, step, assignee_id) values
  ('a1000000-0000-0000-0000-0000000000c1','a1000000-0000-0000-0000-0000000000b1',
   'Structural framework', 1, 1, 'd0000000-0000-0000-0000-000000000002'),
  ('a1000000-0000-0000-0000-0000000000c2','a1000000-0000-0000-0000-0000000000b1',
   'Surface preparation and paint', 2, 2, 'd0000000-0000-0000-0000-000000000002'),
  ('a1000000-0000-0000-0000-0000000000c3','a1000000-0000-0000-0000-0000000000b1',
   'Branding signage', 3, 2, 'd0000000-0000-0000-0000-000000000001');

select t_assert((select count(*) from stage_tasks
                  where stage_id='a1000000-0000-0000-0000-0000000000b1') = 3,
                'T1 the supervisor can break their stage into work items');

-- Somebody else's workshop member has no business in this stage's plan.
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  insert into stage_tasks (stage_id, title, ord)
  values ('a1000000-0000-0000-0000-0000000000b1', 'One I invented', 9)$$,
  'T1 a worker cannot add work items to the stage');

select t_expect_error($$
  delete from stage_tasks where id = 'a1000000-0000-0000-0000-0000000000c1'$$,
  'T1 …nor remove one');

\echo ''
\echo '=== 0033 · the status is the worker''s, the plan is not =========='

-- t1 is theirs, so they may say it is done — through the RPC, which is what
-- records who finished it.
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c1', 'in_progress');
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c1', 'done');
select t_assert((select status from stage_tasks
                  where id='a1000000-0000-0000-0000-0000000000c1') = 'done',
                'T2 the person it was given to can finish it');
select t_assert((select done_by from stage_tasks
                  where id='a1000000-0000-0000-0000-0000000000c1')
                = 'd0000000-0000-0000-0000-000000000002',
                'T2 …and the row records who did');
select t_assert((select done_at from stage_tasks
                  where id='a1000000-0000-0000-0000-0000000000c1') is not null,
                'T2 …and when');

-- A direct write leaves no record, so it is refused — same as a checklist tick.
select t_expect_error($$
  update stage_tasks set status = 'todo'
   where id = 'a1000000-0000-0000-0000-0000000000c1'$$,
  'T2 a direct status write is refused, so the trail has no hole');

-- What it says, who it is for, and what it runs alongside are the plan.
select t_expect_error($$
  update stage_tasks set assignee_id = 'd0000000-0000-0000-0000-000000000001'
   where id = 'a1000000-0000-0000-0000-0000000000c2'$$,
  'T2 a worker cannot hand their own item to somebody else');

select t_expect_error($$
  update stage_tasks set step = 1
   where id = 'a1000000-0000-0000-0000-0000000000c2'$$,
  'T2 …nor move it out of the way of the step waiting on it');

-- An item that is not theirs is not theirs at all.
select t_expect_error($$
  select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c3', 'done')$$,
  'T2 somebody else''s work item cannot be finished for them');

\echo ''
\echo '=== 0033 · sub-stages run in steps too ==========================='

reset role; set test.uid = '';
insert into stage_tasks (id, stage_id, title, ord, step, assignee_id)
values ('a1000000-0000-0000-0000-0000000000c4','a1000000-0000-0000-0000-0000000000b1',
        'Final finishing', 4, 3, 'd0000000-0000-0000-0000-000000000002');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000002';

-- Step 2 still has the branding open, so step 3 is not reachable.
select t_expect_error($$
  select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c4', 'in_progress')$$,
  'T3 a work item waits for the sub-step before it');

-- The two in step 2 are open together — that is the point of a step.
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c2', 'done');
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c3', 'done');

set test.uid = 'd0000000-0000-0000-0000-000000000002';
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c4', 'in_progress');
select t_assert((select status from stage_tasks
                  where id='a1000000-0000-0000-0000-0000000000c4') = 'in_progress',
                'T3 once the whole sub-step is done, the next one opens');

\echo ''
\echo '=== 0033 · the supervisor decides what runs together ============='

-- Not the template: on *this* truck the supervisor can put two items in one
-- step, and the gate follows immediately.
reset role; set test.uid = '';
insert into stage_tasks (id, stage_id, title, ord, step, assignee_id) values
  ('a1000000-0000-0000-0000-0000000000c5','a1000000-0000-0000-0000-0000000000b1',
   'Plumbing', 5, 4, 'd0000000-0000-0000-0000-000000000002'),
  ('a1000000-0000-0000-0000-0000000000c6','a1000000-0000-0000-0000-0000000000b1',
   'Equipment fittings', 6, 5, 'd0000000-0000-0000-0000-000000000002');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c6', 'in_progress')$$,
  'T4 by default the fittings wait for the plumbing');

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the supervisor
update stage_tasks set step = 4 where id = 'a1000000-0000-0000-0000-0000000000c6';

set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c6', 'in_progress')$$,
  'T4 …still waiting, because step 3 is only in progress, not done');

set test.uid = 'd0000000-0000-0000-0000-000000000002';
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c4', 'done');
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c6', 'in_progress');
select t_assert((select status from stage_tasks
                  where id='a1000000-0000-0000-0000-0000000000c6') = 'in_progress',
                'T4 once the supervisor groups them, both open together');

\echo ''
\echo '=== 0033 · an approved stage keeps its breakdown ================='

reset role; set test.uid = '';
update stages set status = 'done' where id = 'a1000000-0000-0000-0000-0000000000b1';

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the supervisor
select t_expect_error($$
  insert into stage_tasks (stage_id, title, ord)
  values ('a1000000-0000-0000-0000-0000000000b1', 'An afterthought', 9)$$,
  'T5 an approved stage''s breakdown cannot be added to');

set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c5', 'done')$$,
  'T5 …nor can a work item on it still be moved');

-- An admin can, because correcting a closed build is their job.
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select public.fn_set_task_status('a1000000-0000-0000-0000-0000000000c5', 'done');
select t_assert((select status from stage_tasks
                  where id='a1000000-0000-0000-0000-0000000000c5') = 'done',
                'T5 an admin can still correct an approved stage');

\echo ''
\echo '=== 0033 · it is audited ========================================='

reset role; set test.uid = '';
select t_assert((select count(*) from audit_log
                  where action = 'set_task_status'
                    and entity_type = 'stage_task') >= 1,
                'T6 moving a work item reaches the audit log');

-- Offboarding anyone must still never fail on a foreign key (0009).
select t_assert((select count(*)
                   from pg_constraint con
                   join pg_attribute att
                     on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
                  where con.contype = 'f'
                    and con.confrelid = 'public.profiles'::regclass
                    and con.confdeltype = 'a'
                    and array_length(con.conkey, 1) = 1
                    and not att.attnotnull) = 0,
                'T6 stage_tasks'' FKs to profiles are ON DELETE SET NULL');

reset role;
\echo ''
\echo '=== 0033 SUB-STAGE TESTS PASSED ================================='

-- ============================================================================
-- Migration 0035 — a build's own PM can set up its plan, in one transaction.
--
-- The case 0031 meant to allow and never did: the build is created with no
-- workflow, and the PM — not the database owner — chooses one. Every build
-- here is inserted with template_id NULL, the way an admin's "leave it to the
-- PM" onboarding leaves it.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0035 · the PM sets up the plan ==============================='

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
select public.fn_save_template('Plan test', null, $j$[
  {"name": "Design",   "days": 3, "step": 1, "discipline": "design"},
  {"name": "Workshop", "days": 9, "step": 2, "discipline": "workshop",
   "tasks": [{"title": "Structural framework", "step": 1}]}
]$j$::jsonb) as tpl \gset
-- A workflow with a stage list that onboarding will refuse cannot be saved
-- through fn_save_template, so the refusal case uses a bare template row.
reset role; set test.uid = '';
insert into workflow_templates (id, name)
values ('b3000000-0000-0000-0000-0000000000e1', 'No stages');

insert into projects (id, code, name, pm_id, status, target_delivery_date) values
  ('b3000000-0000-0000-0000-0000000000a1','AZ-P1','Handed over, no plan',
   'b0000000-0000-0000-0000-000000000002','on_track', current_date + 60),
  ('b3000000-0000-0000-0000-0000000000a2','AZ-P2','Someone else''s build',
   'b0000000-0000-0000-0000-000000000001','on_track', current_date + 60),
  ('b3000000-0000-0000-0000-0000000000a3','AZ-P3','No PM yet',
   null,'on_track', current_date + 60);

set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- AZ-P1's PM
select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a1', :'tpl');

reset role; set test.uid = '';
select t_assert((select template_id from projects
                  where id = 'b3000000-0000-0000-0000-0000000000a1') = :'tpl',
                'P1 the build''s own PM chooses its workflow');
select t_assert((select count(*) from stages
                  where project_id = 'b3000000-0000-0000-0000-0000000000a1') = 2,
                'P1 …and its stages are created in the same call');
select t_assert((select count(*) from stage_tasks st
                   join stages s on s.id = st.stage_id
                  where s.project_id = 'b3000000-0000-0000-0000-0000000000a1') = 1,
                'P1 …with the workshop breakdown');

\echo ''
\echo '=== 0035 · and nothing else gets through ========================='

set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a1',
                               'b3000000-0000-0000-0000-0000000000e1')$$,
  'P2 a plan is chosen once — a build with stages is refused');
select t_expect_error($$
  select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a2',
                               (select id from workflow_templates where name = 'Plan test'))$$,
  'P2 a PM cannot set up another PM''s build');
select t_expect_error($$
  update projects set template_id = 'b3000000-0000-0000-0000-0000000000e1'
   where id = 'b3000000-0000-0000-0000-0000000000a1'$$,
  'P2 a PM still cannot repoint a template by hand');

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- workshop
select t_expect_error($$
  select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a2',
                               (select id from workflow_templates where name = 'Plan test'))$$,
  'P2 a workshop member cannot set up a plan');
-- The NULL case: with no PM on the build, `v_pm = auth.uid()` is NULL.
select t_expect_error($$
  select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a3',
                               (select id from workflow_templates where name = 'Plan test'))$$,
  'P2 …nor anyone else, on a build that has no PM yet');

\echo ''
\echo '=== 0035 · all or nothing ========================================'

set test.uid = 'b0000000-0000-0000-0000-000000000001';        -- AZ-P2's PM
select t_expect_error($$
  select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a2',
                               'b3000000-0000-0000-0000-0000000000e1')$$,
  'P3 a workflow with no stages is refused');
reset role; set test.uid = '';
select t_assert((select template_id from projects
                  where id = 'b3000000-0000-0000-0000-0000000000a2') is null,
                'P3 …and the build is not left pointing at it');

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
select public.fn_set_up_plan('b3000000-0000-0000-0000-0000000000a2', :'tpl');
reset role; set test.uid = '';
select t_assert((select count(*) from stages
                  where project_id = 'b3000000-0000-0000-0000-0000000000a2') = 2,
                'P3 an admin can set up any build''s plan');

reset role;
\echo ''
\echo '=== 0035 SET UP THE PLAN TESTS PASSED ============================'

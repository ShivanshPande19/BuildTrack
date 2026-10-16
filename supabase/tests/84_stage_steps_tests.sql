-- ============================================================================
-- Migration 0031 — stages run in steps: a step opens only when every earlier
-- step is approved, and stages sharing a step run alongside each other.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0031 · a stage waits for its step ============================'

reset role; set test.uid = '';

insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('80000000-0000-0000-0000-0000000000a1','AZ-STEP','Step Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 50);

-- Step 1: design. Step 2: two stages that run alongside each other. Step 3: one.
insert into stages (id, project_id, name, ord, step, status, discipline, assignee_id) values
  ('80000000-0000-0000-0000-0000000000b1','80000000-0000-0000-0000-0000000000a1',
   'Design & Layout', 1, 1, 'todo', 'design',   'c0000000-0000-0000-0000-000000000001'),
  ('80000000-0000-0000-0000-0000000000b2','80000000-0000-0000-0000-0000000000a1',
   'Countertop',      2, 2, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000001'),
  ('80000000-0000-0000-0000-0000000000b3','80000000-0000-0000-0000-0000000000a1',
   'Electricals',     3, 2, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000002'),
  ('80000000-0000-0000-0000-0000000000b4','80000000-0000-0000-0000-0000000000a1',
   'Paint',           4, 3, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000001');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_start_stage('80000000-0000-0000-0000-0000000000b2')$$,
  'S1 a step-2 stage cannot start while the design is still open');

-- The screens read the same rule from one place, so they can never disagree
-- with the RPC about whether a stage is open.
reset role; set test.uid = '';
select t_assert((select is_locked from v_stage_gate
                  where stage_id='80000000-0000-0000-0000-0000000000b2'),
                'S1 …and the gate view says so too');
select t_assert((select blocked_by from v_stage_gate
                  where stage_id='80000000-0000-0000-0000-0000000000b2') = 'Design & Layout',
                'S1 …naming what it is waiting for');
select t_assert((select is_locked from v_stage_gate
                  where stage_id='80000000-0000-0000-0000-0000000000b1') is false,
                'S1 the first step is never locked');

\echo ''
\echo '=== 0031 · finishing a step opens the whole next one =============='

set role authenticated;
set test.uid = 'c0000000-0000-0000-0000-000000000001';        -- the designer
select public.fn_start_stage('80000000-0000-0000-0000-0000000000b1');
select public.fn_submit_stage('80000000-0000-0000-0000-0000000000b1') as a1 \gset
set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the PM
select public.fn_decide_stage(:'a1', true);

reset role; set test.uid = '';
select t_assert((select status from stages
                  where id='80000000-0000-0000-0000-0000000000b2') = 'in_progress',
                'S2 both stages of the next step are pulled into progress');
select t_assert((select status from stages
                  where id='80000000-0000-0000-0000-0000000000b3') = 'in_progress',
                'S2 …not just the first one (the old auto-start took limit 1)');
select t_assert((select status from stages
                  where id='80000000-0000-0000-0000-0000000000b4') = 'todo',
                'S2 …and the step after that stays shut');

-- Both assignees were told, not just one.
select t_assert((select count(*) from notifications
                  where type = 'stage_assigned'
                    and entity_id in ('80000000-0000-0000-0000-0000000000b2',
                                      '80000000-0000-0000-0000-0000000000b3')) = 2,
                'S2 both people are told their stage is up');

\echo ''
\echo '=== 0031 · half a step is not a step ============================='

-- Approving one of the two parallel stages must not open the next step: the
-- paint cannot start while the electricals are still open.
set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select public.fn_submit_stage('80000000-0000-0000-0000-0000000000b2') as a2 \gset
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select public.fn_decide_stage(:'a2', true);

reset role; set test.uid = '';
select t_assert((select status from stages
                  where id='80000000-0000-0000-0000-0000000000b4') = 'todo',
                'S3 the next step stays shut while its sibling is still open');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_start_stage('80000000-0000-0000-0000-0000000000b4')$$,
  'S3 …and it cannot be started by hand either');

-- Finish the sibling and the next step opens.
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select public.fn_submit_stage('80000000-0000-0000-0000-0000000000b3') as a3 \gset
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select public.fn_decide_stage(:'a3', true);

reset role; set test.uid = '';
select t_assert((select status from stages
                  where id='80000000-0000-0000-0000-0000000000b4') = 'in_progress',
                'S3 once the whole step is approved, the next one opens');

\echo ''
\echo '=== 0031 · an admin can put a build back in order ================='

reset role; set test.uid = '';
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('80000000-0000-0000-0000-0000000000a2','AZ-STEP2','Step Build 2',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 50);
insert into stages (id, project_id, name, ord, step, status, discipline, assignee_id) values
  ('80000000-0000-0000-0000-0000000000c1','80000000-0000-0000-0000-0000000000a2',
   'Design', 1, 1, 'todo', 'design',   'c0000000-0000-0000-0000-000000000001'),
  ('80000000-0000-0000-0000-0000000000c2','80000000-0000-0000-0000-0000000000a2',
   'Chassis', 2, 2, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000001');

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
select public.fn_start_stage('80000000-0000-0000-0000-0000000000c2');
select t_assert((select status from stages
                  where id='80000000-0000-0000-0000-0000000000c2') = 'in_progress',
                'S4 an admin can start a stage out of turn — and fn_audit records it');

\echo ''
\echo '=== 0031 · the step is part of the plan, so it is the PM''s ======='

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the assignee
select t_expect_error($$
  update stages set step = 1 where id = '80000000-0000-0000-0000-0000000000c2'$$,
  'S5 the person working a stage cannot move it to another step');

-- The PM can, which is how a plan that came out of the template wrong is fixed
-- on this build without touching the template or any other build using it.
set test.uid = 'b0000000-0000-0000-0000-000000000002';
update stages set step = 1 where id = '80000000-0000-0000-0000-0000000000c2';
select t_assert((select step from stages
                  where id='80000000-0000-0000-0000-0000000000c2') = 1,
                'S5 the build''s PM can group two stages into one step');

\echo ''
\echo '=== 0031 · the plan is laid out a step at a time =================='

-- Two stages in one step share the window; the build is not made longer by
-- running them alongside each other.
reset role; set test.uid = '';
select public.fn_recompute_schedule('80000000-0000-0000-0000-0000000000a1');
select t_assert((select planned_start from stages where id='80000000-0000-0000-0000-0000000000b2')
              = (select planned_start from stages where id='80000000-0000-0000-0000-0000000000b3'),
                'S6 stages in one step start on the same day');
select t_assert((select planned_end from stages where id='80000000-0000-0000-0000-0000000000b2')
              = (select planned_end from stages where id='80000000-0000-0000-0000-0000000000b3'),
                'S6 …and end on the same day');
select t_assert((select planned_end from stages where id='80000000-0000-0000-0000-0000000000b1')
              < (select planned_start from stages where id='80000000-0000-0000-0000-0000000000b2'),
                'S6 …and the step before them finishes first');

\echo ''
\echo '=== 0031 · a project manager can set up their own build ==========='

reset role; set test.uid = '';
insert into projects (id, code, name, template_id, pm_id, status, target_delivery_date)
values ('80000000-0000-0000-0000-0000000000a3','AZ-PMSET','PM Sets This Up',
        '11111111-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 60);

-- A second project manager, created here so this suite does not depend on
-- which spare users an earlier one happened to leave behind.
insert into auth.users (id, email) values
  ('80000000-0000-0000-0000-0000000000f1','otherpm@az.co') on conflict do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('80000000-0000-0000-0000-0000000000f1','Other PM','otherpm@az.co','pm','active')
  on conflict do nothing;

set role authenticated;

-- …but only *their* build.
set test.uid = '80000000-0000-0000-0000-0000000000f1';
select t_expect_error($$
  select public.fn_onboard_project('80000000-0000-0000-0000-0000000000a3')$$,
  'S7 another project manager cannot set up a build that is not theirs');

set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the build's PM
select public.fn_onboard_project('80000000-0000-0000-0000-0000000000a3');
select t_assert((select count(*) from stages
                  where project_id='80000000-0000-0000-0000-0000000000a3') = 7,
                'S7 the build''s own PM can generate its stages');
select t_assert((select count(*) from stages
                  where project_id='80000000-0000-0000-0000-0000000000a3'
                    and step is null) = 0,
                'S7 …and every stage lands in a step, copied from the template');

-- A build with no template is refused rather than quietly producing nothing.
reset role; set test.uid = '';
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('80000000-0000-0000-0000-0000000000a4','AZ-NOPLAN','No Plan Yet',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 60);
set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  select public.fn_onboard_project('80000000-0000-0000-0000-0000000000a4')$$,
  'S7 a build with no template chosen yet is refused, not half-built');

\echo ''
\echo '=== 0031 · every build that already existed is unchanged =========='

reset role; set test.uid = '';
select t_assert((select count(*) from stages s
                  where s.project_id = '77777777-0000-0000-0000-000000000001'
                    and s.step <> s.ord) = 0,
                'S8 an existing build still runs one stage per step');

-- A stage inserted without a step — every fixture in every other suite, and
-- anything written before 0031 — reads as its own step, not as step 1. The
-- column has **no default** for exactly this reason: defaulting it to 1 would
-- make a build silently parallel the moment somebody forgot the column.
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('80000000-0000-0000-0000-0000000000d1','80000000-0000-0000-0000-0000000000a1',
        'Afterthought', 9, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000001');
select t_assert((select step from stages
                  where id='80000000-0000-0000-0000-0000000000d1') is null,
                'S8 a stage inserted without a step keeps it null');
select t_assert((select is_locked from v_stage_gate
                  where stage_id='80000000-0000-0000-0000-0000000000d1') is false,
                'S8 …and reads as its own step (ord 9, everything before it done)');

-- …and it is genuinely gated, not merely ungrouped: put an open stage in front
-- of it and it locks.
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('80000000-0000-0000-0000-0000000000d2','80000000-0000-0000-0000-0000000000a1',
        'Comes first', 8, 'todo', 'workshop', 'd0000000-0000-0000-0000-000000000001');
select t_assert((select is_locked from v_stage_gate
                  where stage_id='80000000-0000-0000-0000-0000000000d1'),
                'S8 …so an unset step still waits for the one before it');

reset role;
\echo ''
\echo '=== 0031 STAGE STEP TESTS PASSED ================================='

-- ============================================================================
-- Migration 0028 — the design stage and the design artifact are the same piece
-- of work, and the app now treats them that way.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the AZ-200
-- fixture, the designer and client users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0028 · a design stage waits for the client ==================='

reset role; set test.uid = '';

insert into projects (id, code, name, client_account_id, pm_id, status, target_delivery_date)
values ('7e000000-0000-0000-0000-0000000000a1','AZ-DSGN','Design Gate Build',
        '99999999-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 45);

insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7e000000-0000-0000-0000-0000000000b1','7e000000-0000-0000-0000-0000000000a1',
        'Design & Layout', 1, 'in_progress', 'design', 'c0000000-0000-0000-0000-000000000001');

-- No design at all yet: the stage is not finished, whatever its checklist says.
set role authenticated;
set test.uid = 'c0000000-0000-0000-0000-000000000001';        -- the designer
select t_expect_error($$
  select public.fn_submit_stage('7e000000-0000-0000-0000-0000000000b1')$$,
  'D1 a design stage cannot be submitted with no approved design on the build');

-- A design in draft is not an approval either.
select public.fn_create_design('7e000000-0000-0000-0000-0000000000a1', 'layout',
  p_image_url => 'https://example.test/draft.png',
  p_submit    => false,
  p_stage     => '7e000000-0000-0000-0000-0000000000b1') as art \gset

select t_expect_error($$
  select public.fn_submit_stage('7e000000-0000-0000-0000-0000000000b1')$$,
  'D1 …nor with one sitting in draft');

-- Submitted to the client is still not approved.
reset role; set test.uid = '';
update design_artifacts set status = 'pending_approval' where id = :'art';
set role authenticated;
set test.uid = 'c0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_submit_stage('7e000000-0000-0000-0000-0000000000b1')$$,
  'D1 …nor while it is still with the client');

\echo ''
\echo '=== 0028 · the client approving is what unblocks it =============='

set test.uid = 'f0000000-0000-0000-0000-000000000001';        -- the client
select public.fn_client_decide_design(:'art', true);

reset role; set test.uid = '';
select t_assert((select status from design_artifacts where id = :'art') = 'approved',
                'D2 the client''s approval lands on the design');

-- …and the person holding the stage is told what it means for their work.
select t_assert((select count(*) from notifications
                  where user_id = 'c0000000-0000-0000-0000-000000000001'
                    and entity_type = 'stage'
                    and entity_id = '7e000000-0000-0000-0000-0000000000b1'
                    and type = 'stage_ready'
                    and title ilike '%can be submitted%') >= 1,
                'D2 the designer is told their stage can move, not just that the design was approved');

-- …and that is a *different* notification from the one about the design, so
-- the feed does not repeat itself and each opens the right thing.
select t_assert((select count(*) from notifications
                  where user_id = 'c0000000-0000-0000-0000-000000000001'
                    and type = 'approved'
                    and entity_type = 'design') >= 1,
                'D2 the design-approved notification is still its own row');

set role authenticated;
set test.uid = 'c0000000-0000-0000-0000-000000000001';
select public.fn_submit_stage('7e000000-0000-0000-0000-0000000000b1') as appr \gset
select t_assert((select count(*) from stage_approvals
                  where stage_id = '7e000000-0000-0000-0000-0000000000b1'
                    and status = 'pending') = 1,
                'D2 with an approved design, the stage submits normally');

\echo ''
\echo '=== 0028 · the rule is scoped to design work ====================='

-- A workshop stage on the same build has no design requirement: it would be
-- absurd for a welder to wait on a layout approval to report their own work.
reset role; set test.uid = '';
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7e000000-0000-0000-0000-0000000000b2','7e000000-0000-0000-0000-0000000000a1',
        'Chassis', 2, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000002');

insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('7e000000-0000-0000-0000-0000000000a2','AZ-WSHOP','Workshop Only',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 45);
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7e000000-0000-0000-0000-0000000000b3','7e000000-0000-0000-0000-0000000000a2',
        'Chassis', 1, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000002');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select public.fn_submit_stage('7e000000-0000-0000-0000-0000000000b3');
select t_assert((select count(*) from stage_approvals
                  where stage_id = '7e000000-0000-0000-0000-0000000000b3') = 1,
                'D3 a workshop stage on a build with no designs submits freely');

\echo ''
\echo '=== 0028 · a design cannot be linked across builds ==============='

set test.uid = 'c0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_create_design('7e000000-0000-0000-0000-0000000000a2', 'layout',
    p_stage => '7e000000-0000-0000-0000-0000000000b1')$$,
  'D4 a design cannot point at a stage on a different build');

\echo ''
\echo '=== 0028 · the checklist is the PM''s to write ==================='

reset role; set test.uid = '';
insert into checklist_items (id, stage_id, label)
values ('7e000000-0000-0000-0000-0000000000c1','7e000000-0000-0000-0000-0000000000b3',
        'Weld the frame');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000002';        -- the assignee

-- Ticking is theirs — through fn_tick_check since 0029.
select public.fn_tick_check('7e000000-0000-0000-0000-0000000000c1', true);
select t_assert((select done from checklist_items
                  where id='7e000000-0000-0000-0000-0000000000c1') is true,
                'D5 the assignee can tick their own checklist');

-- Rewriting what it says is not.
select t_expect_error($$
  update checklist_items set label = 'Something easier'
   where id = '7e000000-0000-0000-0000-0000000000c1'$$,
  'D5 …but cannot change what a checklist item says');

select t_expect_error($$
  insert into checklist_items (stage_id, label)
  values ('7e000000-0000-0000-0000-0000000000b3', 'A check I invented')$$,
  'D5 …nor add their own items');

select t_expect_error($$
  delete from checklist_items where id = '7e000000-0000-0000-0000-0000000000c1'$$,
  'D5 …nor delete one');

-- The PM owns all three.
set test.uid = 'b0000000-0000-0000-0000-000000000002';
update checklist_items set label = 'Weld and square the frame'
 where id = '7e000000-0000-0000-0000-0000000000c1';
select t_assert((select label from checklist_items
                  where id='7e000000-0000-0000-0000-0000000000c1') = 'Weld and square the frame',
                'D5 the PM can correct a checklist item');

insert into checklist_items (stage_id, label)
values ('7e000000-0000-0000-0000-0000000000b3', 'Check the weld seams');
select t_assert((select count(*) from checklist_items
                  where stage_id='7e000000-0000-0000-0000-0000000000b3') = 2,
                'D5 …and add one');

delete from checklist_items
 where stage_id='7e000000-0000-0000-0000-0000000000b3' and label = 'Check the weld seams';
select t_assert((select count(*) from checklist_items
                  where stage_id='7e000000-0000-0000-0000-0000000000b3') = 1,
                'D5 …and remove one');

\echo ''
\echo '=== 0028 · design work is recognised by name ====================='

reset role; set test.uid = '';
select t_assert(public.fn_infer_discipline('Client sign-off') = 'design',
                'D6 "Client sign-off" is design work, not workshop');
select t_assert(public.fn_infer_discipline('Mockup review') = 'design',
                'D6 so is "Mockup review"');
select t_assert(public.fn_infer_discipline('Concept') = 'design',
                'D6 and "Concept"');
-- …without swallowing the approvals that are not design work.
select t_assert(public.fn_infer_discipline('Final approval') = 'workshop',
                'D6 a bare "Final approval" is not design work');
select t_assert(public.fn_infer_discipline('Testing & Delivery') = 'service',
                'D6 and the service rule still wins where it should');

reset role;
\echo ''
\echo '=== 0028 DESIGN STAGE TESTS PASSED =============================='

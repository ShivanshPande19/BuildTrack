-- ============================================================================
-- Migration 0029 — a checklist tick is evidence: it is recorded, it can be made
-- to need a photo, and once the PM approves the stage it is closed.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the AZ-200
-- fixture, the workshop / PM / admin users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0029 · a tick is recorded ===================================='

reset role; set test.uid = '';

insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('7f000000-0000-0000-0000-0000000000a1','AZ-EVID','Evidence Build',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 40);

insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7f000000-0000-0000-0000-0000000000b1','7f000000-0000-0000-0000-0000000000a1',
        'Chassis', 1, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000001');

insert into checklist_items (id, stage_id, label) values
  ('7f000000-0000-0000-0000-0000000000c1','7f000000-0000-0000-0000-0000000000b1','Weld the frame'),
  ('7f000000-0000-0000-0000-0000000000c2','7f000000-0000-0000-0000-0000000000b1','Square the frame');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the fitter

select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c1', true);
select t_assert((select done from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c1') is true,
                'E1 the fitter can tick their own check');
select t_assert((select done_by from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c1')
                = 'd0000000-0000-0000-0000-000000000001',
                'E1 …and the row records who ticked it');
select t_assert((select done_at from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c1') is not null,
                'E1 …and when');

-- Un-ticking drops the record with it: a check that is not done was not done
-- by anybody, and a stale name on it reads as if it were.
select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c1', false);
select t_assert((select done_by from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c1') is null,
                'E1 un-ticking clears the record rather than leaving a stale name');
select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c1', true);

\echo ''
\echo '=== 0029 · the record has no hole ================================'

-- The whole point of the RPC is that done cannot move without being recorded.
-- A direct UPDATE — which is exactly what the app used to do — is refused.
select t_expect_error($$
  update checklist_items set done = true
   where id = '7f000000-0000-0000-0000-0000000000c2'$$,
  'E2 a direct write to done is refused, so the trail cannot be bypassed');

select t_assert((select done from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c2') is false,
                'E2 …and the refused write changed nothing');

-- Nor can the record itself be forged.
select t_expect_error($$
  update checklist_items set done_by = 'b0000000-0000-0000-0000-000000000002'
   where id = '7f000000-0000-0000-0000-0000000000c1'$$,
  'E2 …nor can done_by be set by hand');

\echo ''
\echo '=== 0029 · it is audited ========================================='

reset role; set test.uid = '';
select t_assert((select count(*) from audit_log
                  where action = 'tick_check'
                    and entity_type = 'checklist_item'
                    and entity_id = '7f000000-0000-0000-0000-0000000000c1') >= 1,
                'E3 ticking a check reaches the audit log');
select t_assert((select count(*) from audit_log
                  where action = 'untick_check'
                    and entity_id = '7f000000-0000-0000-0000-0000000000c1') >= 1,
                'E3 …and so does un-ticking it');

\echo ''
\echo '=== 0029 · a check can demand a photo ============================'

reset role; set test.uid = '';
insert into checklist_items (id, stage_id, label, photo_required) values
  ('7f000000-0000-0000-0000-0000000000c3','7f000000-0000-0000-0000-0000000000b1',
   'Pressure-test the gas line', true);

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c3', true)$$,
  'E4 a photo-required check cannot be ticked bare');

-- A photo on *another* stage is not proof of this one. Without this check the
-- id of any attachment in the system would satisfy the rule.
reset role; set test.uid = '';
insert into attachments (id, owner_type, owner_id, file_url, caption)
values ('7f000000-0000-0000-0000-0000000000e9','stage',
        '7c000000-0000-0000-0000-0000000000b2','https://example.test/other.jpg','Elsewhere');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c3', true,
    '7f000000-0000-0000-0000-0000000000e9')$$,
  'E4 …nor with a photo belonging to a different stage');

-- With a photo on this stage it goes through, and the row keeps which photo
-- discharged it — so the PM can open the proof from the check.
reset role; set test.uid = '';
insert into attachments (id, owner_type, owner_id, file_url, caption)
values ('7f000000-0000-0000-0000-0000000000e1','stage',
        '7f000000-0000-0000-0000-0000000000b1','https://example.test/gas.jpg','Gas line');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c3', true,
  '7f000000-0000-0000-0000-0000000000e1');
select t_assert((select proof_attachment_id from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c3')
                = '7f000000-0000-0000-0000-0000000000e1',
                'E4 the photo that discharged the check is kept on the row');

-- A check with no photo rule still ticks with nothing attached: demanding one
-- everywhere is how a fitter learns to photograph the floor.
select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c2', true);
select t_assert((select done from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c2') is true,
                'E4 an ordinary check needs no photo');

\echo ''
\echo '=== 0029 · the photo rule is the PM''s to set ====================='

select t_expect_error($$
  update checklist_items set photo_required = false
   where id = '7f000000-0000-0000-0000-0000000000c3'$$,
  'E5 the fitter cannot switch off a check''s photo requirement');

set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the PM
update checklist_items set photo_required = true
 where id = '7f000000-0000-0000-0000-0000000000c2';
select t_assert((select photo_required from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c2') is true,
                'E5 the PM can require a photo on one build''s check');

\echo ''
\echo '=== 0029 · a template carries the rule to every build ============'

reset role; set test.uid = '';
select t_assert((select count(*) from information_schema.columns
                  where table_name = 'template_stage_checks'
                    and column_name = 'photo_required') = 1,
                'E6 a template check can carry the photo rule');

\echo ''
\echo '=== 0029 · an approved stage is closed ==========================='

-- The freeze. Once the PM approves, the checklist is the evidence they
-- approved, and evidence that can still be edited is not evidence.
set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select public.fn_submit_stage('7f000000-0000-0000-0000-0000000000b1') as ap \gset
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select public.fn_decide_stage(:'ap', true);

reset role; set test.uid = '';
select t_assert((select status from stages
                  where id='7f000000-0000-0000-0000-0000000000b1') = 'done',
                'E7 the stage is approved');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c1', false)$$,
  'E7 the fitter cannot un-tick a check on an approved stage');

-- Not even the PM, who signed it. 0028 gave them the wording; an approval is
-- where that stops.
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  update checklist_items set label = 'Something else'
   where id = '7f000000-0000-0000-0000-0000000000c1'$$,
  'E7 …and the PM cannot reword one either, once it is approved');

select t_expect_error($$
  insert into checklist_items (stage_id, label)
  values ('7f000000-0000-0000-0000-0000000000b1', 'An afterthought')$$,
  'E7 …nor add one to a stage already signed off');

-- An admin can, because correcting a genuine mistake on a closed build is
-- their job — and fn_audit records that it was them.
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select public.fn_tick_check('7f000000-0000-0000-0000-0000000000c1', false);
select t_assert((select done from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c1') is false,
                'E7 an admin can still correct an approved stage''s checklist');

\echo ''
\echo '=== 0029 · a part cannot be fitted into an approved stage ========'

reset role; set test.uid = '';
insert into component_instances (id, item_catalog_id, serial_number, status)
values ('7f000000-0000-0000-0000-0000000000f1','33333333-0000-0000-0000-000000000004',
        'SN-EVID-1','in_stock');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_install_component('7f000000-0000-0000-0000-0000000000f1',
                                     '7f000000-0000-0000-0000-0000000000b1')$$,
  'E8 a part cannot be added to a stage the PM has already approved');

\echo ''
\echo '=== 0029 · a reserved part is not taken off its build ============'

-- Store's intake earmarks a part for a build: status stays in_stock while
-- installed_in_project_id names the build (0026). Fitting it to a different
-- truck used to overwrite that earmark silently.
reset role; set test.uid = '';
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7f000000-0000-0000-0000-0000000000b2','7f000000-0000-0000-0000-0000000000a1',
        'Electricals', 2, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000001');

insert into component_instances (id, item_catalog_id, serial_number, status, installed_in_project_id)
values ('7f000000-0000-0000-0000-0000000000f2','33333333-0000-0000-0000-000000000004',
        'SN-EVID-2','in_stock','7c000000-0000-0000-0000-0000000000a1');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_install_component('7f000000-0000-0000-0000-0000000000f2',
                                     '7f000000-0000-0000-0000-0000000000b2')$$,
  'E9 a part reserved for another build is refused, not quietly re-pointed');

select t_assert((select installed_in_project_id from component_instances
                  where id='7f000000-0000-0000-0000-0000000000f2')
                = '7c000000-0000-0000-0000-0000000000a1',
                'E9 …and the earmark it already had survives');

-- A part reserved for *this* build is exactly what should go in.
reset role; set test.uid = '';
update component_instances set installed_in_project_id = '7f000000-0000-0000-0000-0000000000a1'
 where id = '7f000000-0000-0000-0000-0000000000f2';

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select public.fn_install_component('7f000000-0000-0000-0000-0000000000f2',
                                   '7f000000-0000-0000-0000-0000000000b2');
select t_assert((select status from component_instances
                  where id='7f000000-0000-0000-0000-0000000000f2') = 'installed',
                'E9 a part reserved for this build installs normally');

\echo ''
\echo '=== 0029 · a delay is reported against your own work ============='

-- The fitter is the one who knows why the stage slipped, so they may say so —
-- about their own stage. The per-role grant let any workshop member log a delay
-- against any stage on any build, including one they had never seen.
set test.uid = 'd0000000-0000-0000-0000-000000000001';
insert into delay_logs (stage_id, reason_code, days_delayed, note, logged_by)
values ('7f000000-0000-0000-0000-0000000000b2','procurement', 3,
        'Wiring loom did not arrive', 'd0000000-0000-0000-0000-000000000001');
select t_assert((select count(*) from delay_logs
                  where stage_id='7f000000-0000-0000-0000-0000000000b2') = 1,
                'E10 the fitter can log a delay on their own stage');

select t_expect_error($$
  insert into delay_logs (stage_id, reason_code, days_delayed)
  values ('7e000000-0000-0000-0000-0000000000b3','weather', 2)$$,
  'E10 …but not on a stage that belongs to someone else');

-- Attributing a slip across the whole build stays the PM's job, so they keep
-- the table.
set test.uid = 'b0000000-0000-0000-0000-000000000002';
insert into delay_logs (stage_id, reason_code, days_delayed)
values ('7f000000-0000-0000-0000-0000000000b2','client', 1);
select t_assert((select count(*) from delay_logs
                  where stage_id='7f000000-0000-0000-0000-0000000000b2') = 2,
                'E10 the build''s PM can log a delay on any of its stages');


\echo ''
\echo '=== 0030 · a stage photo is evidence too ========================='

-- 0029 made the tick evidence and left the photos it points at deletable by
-- any staff member at all, including after the PM signed off on them.
reset role; set test.uid = '';
insert into stages (id, project_id, name, ord, status, discipline, assignee_id)
values ('7f000000-0000-0000-0000-0000000000b3','7f000000-0000-0000-0000-0000000000a1',
        'Finishing', 3, 'in_progress', 'workshop', 'd0000000-0000-0000-0000-000000000001');

insert into attachments (id, owner_type, owner_id, file_url, caption, uploaded_by)
values ('7f000000-0000-0000-0000-0000000000e5','stage',
        '7f000000-0000-0000-0000-0000000000b3','https://example.test/weld.jpg','Weld',
        'd0000000-0000-0000-0000-000000000001');

set role authenticated;

-- A workshop member on a different build has no business here.
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  delete from attachments where id = '7f000000-0000-0000-0000-0000000000e5'$$,
  'E11 another fitter cannot delete a photo from someone else''s stage');

-- The person who took it can.
set test.uid = 'd0000000-0000-0000-0000-000000000001';
delete from attachments where id = '7f000000-0000-0000-0000-0000000000e5';
select t_assert((select count(*) from attachments
                  where id='7f000000-0000-0000-0000-0000000000e5') = 0,
                'E11 whoever took the photo can remove it');

-- …and so can the build's PM, whatever they took.
reset role; set test.uid = '';
insert into attachments (id, owner_type, owner_id, file_url, caption, uploaded_by)
values ('7f000000-0000-0000-0000-0000000000e6','stage',
        '7f000000-0000-0000-0000-0000000000b3','https://example.test/weld2.jpg','Weld 2',
        'd0000000-0000-0000-0000-000000000001');
set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';
delete from attachments where id = '7f000000-0000-0000-0000-0000000000e6';
select t_assert((select count(*) from attachments
                  where id='7f000000-0000-0000-0000-0000000000e6') = 0,
                'E11 …and so can the build''s project manager');

\echo ''
\echo '=== 0030 · an approved stage keeps its photos ===================='

-- b1 was approved back in E7. The photo that discharged its gas-line check is
-- part of what the PM signed off, so it stops being deletable — by the person
-- who took it and by the PM alike.
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  delete from attachments where id = '7f000000-0000-0000-0000-0000000000e1'$$,
  'E12 a photo on an approved stage cannot be deleted');

set test.uid = 'b0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  delete from attachments where id = '7f000000-0000-0000-0000-0000000000e1'$$,
  'E12 …not even by the PM who approved it');

select t_assert((select proof_attachment_id from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c3')
                = '7f000000-0000-0000-0000-0000000000e1',
                'E12 …so the check it proves still points at it');

-- An admin can, because correcting a closed build is their job.
set test.uid = 'a0000000-0000-0000-0000-000000000001';
delete from attachments where id = '7f000000-0000-0000-0000-0000000000e1';
select t_assert((select count(*) from attachments
                  where id='7f000000-0000-0000-0000-0000000000e1') = 0,
                'E12 an admin can still remove one');

-- …and the check it proved is left saying so rather than pointing at nothing:
-- proof_attachment_id is ON DELETE SET NULL, and the app reads a ticked
-- photo-required check with no proof as "No photo on record".
select t_assert((select proof_attachment_id from checklist_items
                  where id='7f000000-0000-0000-0000-0000000000c3') is null,
                'E12 …and the check it proved drops the dangling link');

reset role;
\echo ''
\echo '=== 0029 + 0030 EVIDENCE TESTS PASSED ==========================='

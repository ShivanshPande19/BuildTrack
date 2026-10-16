-- ============================================================================
-- Migration 0032 — a designation beside the role, a supervisor flag the app
-- acts on, and a record of which admin brought a build in.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0032 · a designation says what someone does =================='

reset role; set test.uid = '';

-- A second admin, created here rather than assumed: this migration exists
-- *because* there can be more than one, so a suite about it should have two.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000002','finance@az.co') on conflict do nothing;
insert into profiles (id, full_name, email, role, status) values
  ('a0000000-0000-0000-0000-000000000002','Priya Nair','finance@az.co','admin','active')
  on conflict do nothing;

update profiles set designation = 'Operations'
 where id = 'a0000000-0000-0000-0000-000000000001';
update profiles set designation = 'Finance'
 where id = 'a0000000-0000-0000-0000-000000000002';
select t_assert((select count(distinct designation) from profiles
                  where role = 'admin' and designation is not null) = 2,
                'G1 two admins are told apart by what they do, not their role');
select t_assert((select designation from profiles
                  where id='a0000000-0000-0000-0000-000000000001') = 'Operations',
                'G1 an admin can carry a designation beside their role');

-- It is display only: the role is still what every permission is built on, and
-- a designation changes nothing about what they may do.
select t_assert((select role from profiles
                  where id='a0000000-0000-0000-0000-000000000001') = 'admin',
                'G1 …and the role is untouched by it');

\echo ''
\echo '=== 0032 · a supervisor is workshop, not a new role ==============='

update profiles set is_supervisor = true
 where id = 'd0000000-0000-0000-0000-000000000001';
select t_assert((select is_supervisor from profiles
                  where id='d0000000-0000-0000-0000-000000000001'),
                'G2 a workshop member can be marked a supervisor');
select t_assert((select role from profiles
                  where id='d0000000-0000-0000-0000-000000000001') = 'workshop',
                'G2 …and is still workshop, so every workshop rule still applies');

-- The flag only means something inside workshop. A PM marked as a workshop
-- supervisor would be a contradiction the rest of the app cannot read.
select t_expect_error($$
  update profiles set is_supervisor = true
   where id = 'b0000000-0000-0000-0000-000000000002'$$,
  'G2 somebody who is not workshop cannot be a workshop supervisor');

-- Nothing is a supervisor unless it was said so.
select t_assert((select count(*) from profiles
                  where is_supervisor and role <> 'workshop') = 0,
                'G2 no non-workshop profile carries the flag');

\echo ''
\echo '=== 0032 · neither is yours to set about yourself ================='

-- is_supervisor decides who a PM hands workshop work to and who may assign it
-- on, so a workshop member promoting themselves would be a real escalation.
set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error($$
  update profiles set is_supervisor = true
   where id = 'd0000000-0000-0000-0000-000000000002'$$,
  'G2 a workshop member cannot make themselves a supervisor');

select t_expect_error($$
  update profiles set designation = 'Head of Everything'
   where id = 'd0000000-0000-0000-0000-000000000002'$$,
  'G2 …nor give themselves a designation');

-- What was already theirs to edit still is.
update profiles set phone = '+91 99999 00000'
 where id = 'd0000000-0000-0000-0000-000000000002';
select t_assert((select phone from profiles
                  where id='d0000000-0000-0000-0000-000000000002') = '+91 99999 00000',
                'G2 …but their own phone number still is');

\echo ''
\echo '=== 0032 · a build records which admin brought it in =============='

-- The trigger stamps it from the caller, so an admin creating a build does not
-- have to remember to set it.
set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('90000000-0000-0000-0000-0000000000a1','AZ-WHO','Who Made This',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 40);

reset role; set test.uid = '';
select t_assert((select created_by from projects
                  where id='90000000-0000-0000-0000-0000000000a1')
                = 'a0000000-0000-0000-0000-000000000001',
                'G3 a new build records the admin who created it');

-- An explicit value is respected rather than overwritten, so a backfill or a
-- migration can set it.
set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';
insert into projects (id, code, name, pm_id, created_by, status, target_delivery_date)
values ('90000000-0000-0000-0000-0000000000a2','AZ-WHO2','Explicit',
        'b0000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000002','on_track', current_date + 40);
reset role; set test.uid = '';
select t_assert((select created_by from projects
                  where id='90000000-0000-0000-0000-0000000000a2')
                = 'a0000000-0000-0000-0000-000000000002',
                'G3 …and an explicit creator is not overwritten');

-- A row written with no JWT — seed, SQL editor, a backfill — simply has none,
-- rather than being attributed to nobody in particular.
insert into projects (id, code, name, pm_id, status, target_delivery_date)
values ('90000000-0000-0000-0000-0000000000a3','AZ-WHO3','No JWT',
        'b0000000-0000-0000-0000-000000000002','on_track', current_date + 40);
select t_assert((select created_by from projects
                  where id='90000000-0000-0000-0000-0000000000a3') is null,
                'G3 a build written with no signed-in user records no creator');

-- The AZ-200 fixture was onboarded by the admin in 10_workflow, and the
-- backfill reads that out of the audit log rather than leaving it blank.
select t_assert((select created_by from projects
                  where id='77777777-0000-0000-0000-000000000001') is not null,
                'G3 an existing build was backfilled from the audit log');

\echo ''
\echo '=== 0032 · offboarding an admin never fails on a build ============'

-- Same invariant as every other nullable FK to profiles (0009): a person can
-- always be removed, and what they created keeps existing without them.
select t_assert((select count(*)
                   from pg_constraint con
                   join pg_attribute att
                     on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
                  where con.contype = 'f'
                    and con.confrelid = 'public.profiles'::regclass
                    and con.confdeltype = 'a'
                    and array_length(con.conkey, 1) = 1
                    and not att.attnotnull) = 0,
                'G4 projects.created_by is ON DELETE SET NULL like the rest');

reset role;
\echo ''
\echo '=== 0032 DESIGNATION TESTS PASSED ================================'

-- ============================================================================
-- Project dossier (migration 0022): delay attribution view v_project_delays.
-- Reuses the AZ-200 build. t_assert / t_expect_error from 10_workflow_tests.sql.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== DOSSIER · delay attribution ==================================='

-- log a delay against one of AZ-200's stages (as the DB owner, like a backfill)
reset role; set test.uid = '';
insert into delay_logs (stage_id, reason_code, days_delayed, note, logged_by)
select id, 'workshop_capacity', 3, 'Welder was on another build.', 'a0000000-0000-0000-0000-000000000001'
  from stages
 where project_id = '77777777-0000-0000-0000-000000000001' and name = 'Interior & Equipment';

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';                 -- admin
select t_assert((select count(*) from v_project_delays
                  where project_id = '77777777-0000-0000-0000-000000000001') >= 1,
                'PD1 the build''s delays show on the dossier view');
select t_assert((select days_delayed from v_project_delays
                  where project_id = '77777777-0000-0000-0000-000000000001'
                    and stage_name = 'Interior & Equipment' limit 1) = 3,
                'PD2 the view carries how many days the stage slipped');
select t_assert((select logged_by_name from v_project_delays
                  where project_id = '77777777-0000-0000-0000-000000000001'
                    and stage_name = 'Interior & Equipment' limit 1) = 'Anita Owner',
                'PD3 the view attributes who logged the delay');
select t_assert((select reason_code::text from v_project_delays
                  where project_id = '77777777-0000-0000-0000-000000000001'
                    and stage_name = 'Interior & Equipment' limit 1) = 'workshop_capacity',
                'PD4 the reason is on the record');

-- a client cannot read the delay ledger (RLS on delay_logs still applies)
set test.uid = 'f0000000-0000-0000-0000-000000000001';                 -- client
select t_assert((select count(*) from v_project_delays) = 0,
                'PD5 delay attribution stays off the client');

reset role;
\echo ''
\echo '=== DOSSIER TESTS PASSED =========================================='

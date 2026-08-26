-- ============================================================================
-- Per-truck record (migration 0023): v_truck_components.
-- Uses the seed build AZ-118 (a Samsung TV is installed on it) and AZ-200 (the
-- workflow suite installed an inverter). t_assert from 10_workflow_tests.sql.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== TRUCK RECORD · installed components per build ================='

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';                 -- admin

-- the seed installs a Samsung TV on AZ-118 (with bill + warranty)
select t_assert((select count(*) from v_truck_components
                  where project_id = '55555555-0000-0000-0000-000000000001') >= 1,
                'TR1 a build lists the components installed on it');
select t_assert((select item_name from v_truck_components
                  where serial_number = 'SN-88213-KD') = 'Samsung 42" TV',
                'TR2 the record carries the item + serial');
select t_assert((select warranty_end from v_truck_components
                  where serial_number = 'SN-88213-KD') is not null
            and (select bill_url from v_truck_components
                  where serial_number = 'SN-88213-KD') is not null,
                'TR3 the record carries the warranty + the bill');

-- the workflow suite installed an inverter (SN-TEST-001) on AZ-200
select t_assert((select count(*) from v_truck_components
                  where serial_number = 'SN-TEST-001'
                    and project_id = '77777777-0000-0000-0000-000000000001') = 1,
                'TR4 a workshop-installed part is traceable to its truck');

-- costs / bills / the physical record stay off the client
set test.uid = 'f0000000-0000-0000-0000-000000000001';                 -- client
select t_assert((select count(*) from v_truck_components) = 0,
                'TR5 the truck component record stays off the client');

reset role;
\echo ''
\echo '=== TRUCK RECORD TESTS PASSED ====================================='

-- ============================================================================
-- Migration 0034 — a workflow template is saved in one transaction, can carry
-- the workshop breakdown, and onboarding copies that breakdown onto the build.
--
-- Runs after 10_workflow_tests.sql (t_assert / t_expect_error, the users).
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

\echo ''
\echo '=== 0034 · a whole plan in one call =============================='

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin

select public.fn_save_template('Food truck — standard', 'Food truck', $j$[
  {"name": "Design & layout", "days": 4, "step": 1, "discipline": "design",
   "checks": [{"label": "Layout signed by client", "photo_required": false}]},
  {"name": "Workshop", "days": 14, "step": 2, "discipline": "workshop",
   "items":  [{"item_catalog_id": "33333333-0000-0000-0000-000000000004", "qty": 2}],
   "checks": [{"label": "Frame squared", "photo_required": true}],
   "tasks":  [
     {"title": "Structural framework", "step": 1},
     {"title": "Exterior cladding",    "step": 2},
     {"title": "Surface preparation and paint", "step": 3},
     {"title": "Branding signage",     "step": 3},
     {"title": "Final finishing",      "step": 4}]},
  {"name": "Testing", "days": 2, "step": 3, "discipline": "service"}
]$j$::jsonb) as tpl \gset

reset role; set test.uid = '';
select t_assert((select count(*) from template_stages where template_id = :'tpl') = 3,
                'W1 every stage is written');
select t_assert((select count(*) from template_stage_tasks tst
                   join template_stages ts on ts.id = tst.template_stage_id
                  where ts.template_id = :'tpl') = 5,
                'W1 …with the workshop breakdown on its stage');
select t_assert((select count(*) from template_stage_tasks tst
                   join template_stages ts on ts.id = tst.template_stage_id
                  where ts.template_id = :'tpl' and tst.step = 3) = 2,
                'W1 …keeping which items run together (paint and branding)');
select t_assert((select photo_required from template_stage_checks tsc
                   join template_stages ts on ts.id = tsc.template_stage_id
                  where ts.template_id = :'tpl' and tsc.label = 'Frame squared'),
                'W1 …and which checks need a photo');
select t_assert((select discipline from template_stages
                  where template_id = :'tpl' and name = 'Testing') = 'service',
                'W1 an explicit discipline is kept, not re-inferred from the name');
select t_assert((select created_by from workflow_templates where id = :'tpl')
                = 'a0000000-0000-0000-0000-000000000001',
                'W1 the template records who made it');

\echo ''
\echo '=== 0034 · a PM can build one too, a fitter cannot ==============='

set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- PM
select public.fn_save_template('PM''s own', null, '[{"name": "Only stage"}]'::jsonb) as tpl_pm \gset
reset role; set test.uid = '';
select t_assert((select count(*) from workflow_templates where id = :'tpl_pm') = 1,
                'W2 a project manager can create a workflow');
select t_assert((select step from template_stages where template_id = :'tpl_pm') = 1,
                'W2 …and a stage with no step given lands in its own');

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- workshop
select t_expect_error($$
  select public.fn_save_template('Not mine to make', null, '[{"name": "X"}]'::jsonb)$$,
  'W2 a workshop member cannot create a workflow');

\echo ''
\echo '=== 0034 · all or nothing ========================================'

set test.uid = 'a0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_save_template('   ', null, '[{"name": "X"}]'::jsonb)$$,
  'W3 a workflow needs a name');
select t_expect_error($$
  select public.fn_save_template('Empty', null, '[]'::jsonb)$$,
  'W3 …and at least one stage');

-- The second stage has no name. The first stage was already inserted when the
-- error fires — the transaction must take it back with it.
select t_expect_error($$
  select public.fn_save_template('Half written', null,
    '[{"name": "First"}, {"name": "  "}]'::jsonb)$$,
  'W3 a stage with no name is refused');
reset role; set test.uid = '';
select t_assert((select count(*) from workflow_templates where name = 'Half written') = 0,
                'W3 …and nothing of that workflow survives, not even its first stage');

set role authenticated;
set test.uid = 'a0000000-0000-0000-0000-000000000001';
select t_expect_error($$
  select public.fn_save_template('Bad discipline', null,
    '[{"name": "X", "discipline": "carpentry"}]'::jsonb)$$,
  'W3 a discipline that is not a role is refused, not stored');

\echo ''
\echo '=== 0034 · onboarding brings the breakdown with it ==============='

reset role; set test.uid = '';
insert into projects (id, code, name, template_id, pm_id, status, target_delivery_date)
values ('b2000000-0000-0000-0000-0000000000a1','AZ-TPL','From the template',
        :'tpl', 'b0000000-0000-0000-0000-000000000002','on_track', current_date + 60);

set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the build's PM
select public.fn_onboard_project('b2000000-0000-0000-0000-0000000000a1');

reset role; set test.uid = '';
select t_assert((select count(*) from stage_tasks st
                   join stages s on s.id = st.stage_id
                  where s.project_id = 'b2000000-0000-0000-0000-0000000000a1'
                    and s.name = 'Workshop') = 5,
                'W4 the workshop stage arrives with its work items');
select t_assert((select count(*) from stage_tasks st
                   join stages s on s.id = st.stage_id
                  where s.project_id = 'b2000000-0000-0000-0000-0000000000a1'
                    and st.assignee_id is not null) = 0,
                'W4 …all unassigned — who does them is the supervisor''s call');
select t_assert((select count(*) from stage_tasks st
                   join stages s on s.id = st.stage_id
                  where s.project_id = 'b2000000-0000-0000-0000-0000000000a1'
                    and st.step = 3) = 2,
                'W4 …with paint and branding still running together');
select t_assert((select count(*) from stage_tasks st
                   join stages s on s.id = st.stage_id
                  where s.project_id = 'b2000000-0000-0000-0000-0000000000a1'
                    and s.name <> 'Workshop') = 0,
                'W4 a stage with no breakdown in the template gets none');

-- Running it again must not duplicate anything.
set role authenticated;
set test.uid = 'b0000000-0000-0000-0000-000000000002';
select public.fn_onboard_project('b2000000-0000-0000-0000-0000000000a1');
reset role; set test.uid = '';
select t_assert((select count(*) from stage_tasks st
                   join stages s on s.id = st.stage_id
                  where s.project_id = 'b2000000-0000-0000-0000-0000000000a1') = 5,
                'W4 onboarding twice does not duplicate the breakdown');

\echo ''
\echo '=== 0034 · the audit and the FK invariant ========================'

select t_assert((select count(*) from audit_log
                  where action = 'create_template' and entity_id = :'tpl') = 1,
                'W5 creating a workflow is audited');
select t_assert((select count(*)
                   from pg_constraint con
                   join pg_attribute att
                     on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
                  where con.contype = 'f'
                    and con.confrelid = 'public.profiles'::regclass
                    and con.confdeltype = 'a'
                    and array_length(con.conkey, 1) = 1
                    and not att.attnotnull) = 0,
                'W5 workflow_templates.created_by is ON DELETE SET NULL like the rest');

reset role;
\echo ''
\echo '=== 0034 WORKFLOW TEMPLATE TESTS PASSED =========================='

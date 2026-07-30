-- ============================================================================
-- Functional tests for the Admin → PM → staff chain, run as real (non-superuser)
-- users so RLS + the guard triggers are actually exercised.
-- ============================================================================
\set QUIET on
set client_min_messages = notice;

create or replace function t_assert(p_cond boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_cond is not true then raise exception 'TEST FAIL: %', p_label; end if;
  raise notice 'PASS   %', p_label;
end $$;

create or replace function t_expect_error(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
    raise exception 'TEST FAIL: % — expected to be blocked but it succeeded', p_label;
  exception when others then
    if sqlerrm like 'TEST FAIL%' then raise; end if;
    raise notice 'PASS   %  ->  %', p_label, left(sqlerrm, 88);
  end;
end $$;

-- ── people ──────────────────────────────────────────────────────────────────
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001','admin@az.co'),
  ('b0000000-0000-0000-0000-000000000001','pm1@az.co'),
  ('b0000000-0000-0000-0000-000000000002','pm2@az.co'),
  ('c0000000-0000-0000-0000-000000000001','designer@az.co'),
  ('d0000000-0000-0000-0000-000000000001','welder@az.co'),
  ('d0000000-0000-0000-0000-000000000002','welder2@az.co'),
  ('e0000000-0000-0000-0000-000000000001','store@az.co'),
  ('f0000000-0000-0000-0000-000000000001','client@chai.co');

insert into profiles (id, full_name, email, role, status) values
  ('a0000000-0000-0000-0000-000000000001','Anita Owner','admin@az.co','admin','active'),
  ('b0000000-0000-0000-0000-000000000001','Priya PM','pm1@az.co','pm','active'),
  ('b0000000-0000-0000-0000-000000000002','Rahul PM','pm2@az.co','pm','active'),
  ('c0000000-0000-0000-0000-000000000001','Dev Designer','designer@az.co','design','active'),
  ('d0000000-0000-0000-0000-000000000001','Wasim Welder','welder@az.co','workshop','active'),
  ('d0000000-0000-0000-0000-000000000002','Vikram Welder','welder2@az.co','workshop','active'),
  ('e0000000-0000-0000-0000-000000000001','Sana Store','store@az.co','store','active'),
  ('f0000000-0000-0000-0000-000000000001','Chai Client','client@chai.co','client','active');

insert into client_accounts (id, business_name, contact_user_id, email) values
  ('99999999-0000-0000-0000-000000000001','Chai Point','f0000000-0000-0000-0000-000000000001','client@chai.co');

-- a BOM on the template's Electrical stage, so onboarding must auto-generate
-- procurement requirements (Hero #1)
insert into template_stage_items (template_stage_id, item_catalog_id, qty)
select ts.id, '33333333-0000-0000-0000-000000000002', 2
  from template_stages ts
 where ts.template_id = '11111111-0000-0000-0000-000000000001' and ts.name = 'Electrical work';

\echo ''
\echo '=== STEP 1 · Admin creates the project ============================='

set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- a welder
select t_expect_error($$
  insert into projects (code, name, template_id, target_delivery_date)
  values ('AZ-666','Rogue Truck','11111111-0000-0000-0000-000000000001', current_date + 60)
$$, 'C1 workshop staff cannot create a project');

set test.uid = 'b0000000-0000-0000-0000-000000000001';        -- a PM
select t_expect_error($$
  insert into projects (code, name, template_id, pm_id, target_delivery_date)
  values ('AZ-667','PM Self Truck','11111111-0000-0000-0000-000000000001',
          'b0000000-0000-0000-0000-000000000001', current_date + 60)
$$, 'C1 a PM cannot create a project and hand it to themselves');

set test.uid = 'a0000000-0000-0000-0000-000000000001';        -- admin
insert into projects (id, code, name, client_account_id, template_id, target_delivery_date)
values ('77777777-0000-0000-0000-000000000001','AZ-200','Juice Express',
        '99999999-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001',
        current_date + 60);

select t_expect_error(
  $$select public.fn_onboard_project('77777777-0000-0000-0000-000000000001')$$,
  'B1 onboarding is refused while the build has no project manager');

\echo ''
\echo '=== STEP 2 · Admin assigns the PM ================================='

select t_expect_error(
  $$select public.fn_assign_pm('77777777-0000-0000-0000-000000000001',
                               'c0000000-0000-0000-0000-000000000001')$$,
  'B2 a designer cannot be made project manager');

select public.fn_assign_pm('77777777-0000-0000-0000-000000000001',
                           'b0000000-0000-0000-0000-000000000001');
select t_assert((select pm_id from projects where code = 'AZ-200')
                = 'b0000000-0000-0000-0000-000000000001', 'B1 PM assigned after creation');
reset role;   -- notifications are private to their owner, so peek as the DB owner
select t_assert((select count(*) from notifications
                  where user_id = 'b0000000-0000-0000-0000-000000000001'
                    and type = 'project_assigned') = 1,
                'B4 the PM is notified that a build is now theirs');
set role authenticated;
select t_assert((select pm_assigned_by from projects where code = 'AZ-200')
                = 'a0000000-0000-0000-0000-000000000001', 'B6 assignment is attributed');

select public.fn_onboard_project('77777777-0000-0000-0000-000000000001');
select t_assert((select count(*) from stages
                  where project_id = '77777777-0000-0000-0000-000000000001') = 7,
                'A5 stages generated from the template');
select t_assert((select discipline from stages
                  where project_id = '77777777-0000-0000-0000-000000000001'
                    and name = 'Design & Layout') = 'design',
                'D1 the design stage carries discipline=design');
select t_assert((select discipline from stages
                  where project_id = '77777777-0000-0000-0000-000000000001'
                    and name = 'Chassis & Structure') = 'workshop',
                'D1 the chassis stage carries discipline=workshop');
select t_assert((select count(*) from procurement_requirements
                  where project_id = '77777777-0000-0000-0000-000000000001') = 1,
                'Hero#1 requirement auto-generated from the template BOM');
select t_assert((select order_by_date is not null from procurement_requirements
                  where project_id = '77777777-0000-0000-0000-000000000001'),
                'Hero#1 order-by date computed');

\echo ''
\echo '=== STEP 3+4 · PM assigns stages to the right discipline ==========='

set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the OTHER PM
select t_expect_error(format($$select public.fn_assign_stage(%L,%L)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Design & Layout'), 'c0000000-0000-0000-0000-000000000001'),
  'D4 a PM cannot assign stages on a build that is not theirs');

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- a welder
-- RLS hides the row from him, so this changes nothing (no error — 0 rows).
update stages set assignee_id = 'd0000000-0000-0000-0000-000000000001'
 where project_id = '77777777-0000-0000-0000-000000000001' and name = 'Chassis & Structure';
select t_assert((select assignee_id from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Chassis & Structure') is null,
                'D4 staff cannot assign work to themselves by writing the table');
-- and once he IS on a stage, he still cannot hand it to someone else
update stages set discipline = 'design'
 where project_id = '77777777-0000-0000-0000-000000000001' and name = 'Design & Layout';
select t_assert((select discipline from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Design & Layout') = 'design',
                'D4 staff cannot re-plan a stage they do not own');

set test.uid = 'b0000000-0000-0000-0000-000000000001';        -- the real PM
select t_expect_error(format($$select public.fn_assign_stage(%L,%L)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Design & Layout'), 'd0000000-0000-0000-0000-000000000001'),
  'D1 a welder is refused on a design stage without an explicit override');

select t_expect_error(format($$select public.fn_assign_stage(%L,%L)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Design & Layout'), 'b0000000-0000-0000-0000-000000000002'),
  'D1 stages cannot be assigned to a PM/admin/procurement role');

-- the correct assignment: design stage → designer, with dates
select public.fn_assign_stage(
  (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
    and name='Design & Layout'),
  'c0000000-0000-0000-0000-000000000001', current_date, current_date + 4);

select t_assert((select assignee_id from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Design & Layout') = 'c0000000-0000-0000-0000-000000000001',
                'D1 design stage assigned to the designer');
select t_assert((select assigned_due from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Design & Layout') = current_date + 4,
                'D2 the assignment carries a due date');
reset role;
select t_assert((select count(*) from notifications
                  where user_id='c0000000-0000-0000-0000-000000000001'
                    and type='stage_assigned') = 1,
                'D3 the assignee is notified');
set role authenticated;

select t_expect_error(format($$select public.fn_assign_stage(%L,%L,null,null,false)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Design & Layout'), 'd0000000-0000-0000-0000-000000000002'),
  'D5 due-date/discipline rules still hold on reassignment');

-- workshop stage → welder
select public.fn_assign_stage(
  (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
    and name='Chassis & Structure'),
  'd0000000-0000-0000-0000-000000000001', current_date, current_date + 7);

\echo ''
\echo '=== STEP 5 · The assignee works and submits ========================'

set test.uid = 'd0000000-0000-0000-0000-000000000002';        -- the wrong welder
select t_expect_error(format($$select public.fn_start_stage(%L)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Chassis & Structure')),
  'E2 only the assigned member can start a stage');

set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- the assignee
select public.fn_start_stage((select id from stages
  where project_id='77777777-0000-0000-0000-000000000001' and name='Chassis & Structure'));
select t_assert((select status from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Chassis & Structure') = 'in_progress',
                'E2 starting work moves the stage to in_progress');
select t_assert((select current_stage_id from projects where code='AZ-200')
                = (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Chassis & Structure'),
                'F2 projects.current_stage_id now tracks reality');

-- Store logs a part, the assignee installs it into their stage
reset role; set test.uid = '';
insert into component_instances (id, item_catalog_id, serial_number, status)
values ('88888888-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-000000000002','SN-TEST-001','in_stock');
set role authenticated;

set test.uid = 'd0000000-0000-0000-0000-000000000002';
select t_expect_error(format($$select public.fn_install_component(%L,%L)$$,
    '88888888-0000-0000-0000-000000000001',
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Chassis & Structure')),
  'E9 a member who is not on the stage cannot install parts into it');

set test.uid = 'd0000000-0000-0000-0000-000000000001';
select public.fn_install_component('88888888-0000-0000-0000-000000000001',
  (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
    and name='Chassis & Structure'));
select t_assert((select installed_in_project_id from component_instances
                  where id='88888888-0000-0000-0000-000000000001')
                = '77777777-0000-0000-0000-000000000001',
                'Hero#2 the part is now traceable to the truck + stage');
select t_expect_error($$select public.fn_install_component(
    '88888888-0000-0000-0000-000000000001',
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Electrical work'))$$,
  'E9 an already-installed part cannot be installed again');

-- submit for approval
select public.fn_submit_stage((select id from stages
  where project_id='77777777-0000-0000-0000-000000000001' and name='Chassis & Structure'));
select t_assert((select approver_id from stage_approvals
                  where stage_id = (select id from stages
                    where project_id='77777777-0000-0000-0000-000000000001'
                      and name='Chassis & Structure'))
                = 'b0000000-0000-0000-0000-000000000001',
                'E3 the submission is addressed to the build''s PM');
select t_expect_error(format($$select public.fn_submit_stage(%L)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Chassis & Structure')),
  'E5 the same stage cannot be submitted twice');
reset role;
select t_assert((select count(*) from notifications
                  where user_id='b0000000-0000-0000-0000-000000000001'
                    and type='stage_submitted') = 1,
                'E3 the PM is notified about the submission');
set role authenticated;

\echo ''
\echo '=== PM approves → build advances =================================='

set test.uid = 'b0000000-0000-0000-0000-000000000002';        -- the other PM
select t_expect_error(format($$select public.fn_decide_stage(%L, true)$$,
    (select id from stage_approvals order by created_at desc limit 1)),
  'E6 only the build''s own PM can approve its stages');

set test.uid = 'b0000000-0000-0000-0000-000000000001';
select public.fn_decide_stage(
  (select id from stage_approvals where status='pending' order by created_at desc limit 1), true);

select t_assert((select status from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Chassis & Structure') = 'done',
                'E6 approval marks the stage done');
select t_assert((select actual_end is not null from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Chassis & Structure'),
                'E6 actual_end is stamped');
select t_assert((select status from stages
                  where project_id='77777777-0000-0000-0000-000000000001'
                    and name='Exterior cladding') = 'in_progress',
                'E6 the next stage is pulled into progress automatically');
select t_assert((select progress_pct from projects where code='AZ-200') = 14,
                'progress recomputed (1 of 7 stages done)');
reset role;
select t_assert((select count(*) from notifications
                  where user_id='f0000000-0000-0000-0000-000000000001'
                    and type='stage_done') = 1,
                'B4 the client is told their build progressed');
set role authenticated;

\echo ''
\echo '=== Client design approval (was a silent no-op) ===================='

set test.uid = 'c0000000-0000-0000-0000-000000000001';        -- designer
insert into design_artifacts (id, project_id, type, status, created_by)
values ('66666666-0000-0000-0000-000000000001','77777777-0000-0000-0000-000000000001',
        'layout','pending_approval','c0000000-0000-0000-0000-000000000001');
insert into design_versions (id, artifact_id, version_no, file_url)
values ('65666666-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001',1,'x.png');
update design_artifacts set current_version_id='65666666-0000-0000-0000-000000000001'
 where id='66666666-0000-0000-0000-000000000001';

set test.uid = 'f0000000-0000-0000-0000-000000000001';        -- the client
select t_assert((select count(*) from projects) = 1,
                'a client only ever sees their own build');
select t_assert((select count(*) from profiles) = 1,
                'F4 a client can no longer read the staff directory');
select t_assert((select count(*) from v_order_due) = 0,
                'F3 v_order_due no longer leaks procurement data to clients');

-- the old code did a direct UPDATE here, which silently changed nothing
update design_artifacts set status='approved' where id='66666666-0000-0000-0000-000000000001';
select t_assert((select status from design_artifacts
                  where id='66666666-0000-0000-0000-000000000001') = 'pending_approval',
                'E8 a direct client UPDATE is (still) powerless — that was the bug');

select public.fn_client_decide_design('66666666-0000-0000-0000-000000000001', true);
select t_assert((select status from design_artifacts
                  where id='66666666-0000-0000-0000-000000000001') = 'approved',
                'E8 fn_client_decide_design actually approves the design');
select t_assert((select count(*) from design_approvals
                  where version_id='65666666-0000-0000-0000-000000000001') = 1,
                'E8 a real approval record is written');

reset role;
select t_assert((select count(*) from notifications
                  where user_id='c0000000-0000-0000-0000-000000000001'
                    and type='approved') = 1,
                'E8 the designer is notified of the decision');
set role authenticated;
set test.uid = 'f0000000-0000-0000-0000-000000000001';
select t_expect_error($$select public.fn_client_decide_design(
    '66666666-0000-0000-0000-000000000001', true)$$,
  'E8 a design that is not awaiting approval cannot be decided again');

\echo ''
\echo '=== Cross-cutting: status engine, recall, offboarding =============='

-- push a stage past its planned end → the build must report itself delayed
reset role; set test.uid = '';
update stages set planned_end = current_date - 3
 where project_id='77777777-0000-0000-0000-000000000001' and name='Interior & Equipment';
select public.fn_recompute_status('77777777-0000-0000-0000-000000000001');
select t_assert((select status from projects where code='AZ-200') = 'delayed',
                'F1 an overrun stage flips the build to delayed');

set role authenticated;
set test.uid = 'e0000000-0000-0000-0000-000000000001';        -- store
select t_assert(public.fn_recall_notify('33333333-0000-0000-0000-000000000002',
                  'Batch fault — please inspect.') = 1,
                'E10 recall notifies every affected build');
set test.uid = 'd0000000-0000-0000-0000-000000000001';        -- workshop
select t_expect_error($$select public.fn_recall_notify(
    '33333333-0000-0000-0000-000000000002')$$,
  'E10 only store/service/admin can raise a recall');

-- offboarding a PM who owns builds used to fail on a foreign key
reset role; set test.uid = '';
delete from auth.users where id = 'b0000000-0000-0000-0000-000000000001';
select t_assert((select pm_id from projects where code='AZ-200') is null,
                'F5 removing a member no longer fails — references are nulled');

-- and now a submission would be a black hole, so it is refused
set role authenticated;
set test.uid = 'd0000000-0000-0000-0000-000000000001';
select t_expect_error(format($$select public.fn_submit_stage(%L)$$,
    (select id from stages where project_id='77777777-0000-0000-0000-000000000001'
      and name='Exterior cladding')),
  'E4 work cannot be submitted into a build that has no PM');

reset role;
\echo ''
\echo '=== ALL TESTS PASSED =============================================='

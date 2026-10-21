-- 0035_a_pm_can_set_up_the_plan.sql
--
-- 0031 let a project manager onboard their own build, so an admin could hand
-- one over with no plan and the PM would set it up. Half of that never worked.
-- Setting a build's plan is two writes — choose the workflow
-- (`projects.template_id`), then `fn_onboard_project` — and the first is a
-- plain UPDATE that `trg_guard_projects` (0009) refuses for anyone but an
-- admin. So the PM tapped "Set up the plan" and was told they had no
-- permission. 0031's tests created their builds with the template already in
-- place, as the database owner, so the PM's real path was never exercised.
--
-- It is also two writes from the app, which is its own bug: a workflow with no
-- stages is refused by `fn_onboard_project`, after the template has already
-- been recorded on the build.
--
-- `fn_set_up_plan` does both in one transaction, for an admin or the build's
-- own PM, and only while the build has no stages — the plan is chosen once. The
-- guard lets `template_id` through only for that function, the same
-- sanctioned-write pattern as `buildtrack.stage_rpc` (0026). A PM still cannot
-- repoint a build's template by hand.
--
-- Idempotent: one function replaced (0009's body, one condition changed), one
-- added.

-- ════════════════════════════════════════════════════════════════════════════
-- 1. The guard: unchanged from 0009 except that `template_id` may move inside
--    fn_set_up_plan.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_guard_projects() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- No JWT = service role / SQL editor / cron / seed. RLS already blocks anon,
  -- so anything reaching here without a user is trusted server-side work.
  if auth.uid() is null then return new; end if;
  if public.is_admin() then return new; end if;

  -- Clearing pm_id is what an ON DELETE SET NULL cascade does when a PM is
  -- offboarded; RLS already stops a PM from doing it by hand (its WITH CHECK
  -- demands pm_id = auth.uid()). Only *taking* a build is blocked here.
  if new.pm_id is distinct from old.pm_id and new.pm_id is not null then
    raise exception 'Only an admin can change a build''s project manager.' using errcode = '42501';
  end if;
  if new.code              is distinct from old.code
     or new.client_account_id is distinct from old.client_account_id
     or (new.template_id      is distinct from old.template_id
         -- fn_set_up_plan (below) sets it for the build's own PM, in the same
         -- transaction that onboards the build. Nothing else may.
         and coalesce(current_setting('buildtrack.plan_rpc', true), '') <> 'on') then
    raise exception 'Only an admin can change a build''s code, client or workflow template.'
      using errcode = '42501';
  end if;
  return new;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Choose the workflow and create the plan, in one go
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_set_up_plan(p_project uuid, p_template uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pm uuid;
begin
  select pm_id into v_pm from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  -- coalesce: on a build with no PM, `v_pm = auth.uid()` is NULL, and
  -- `not (false or null)` is NULL — which an IF treats as "not refused".
  if not (public.is_admin() or coalesce(v_pm = auth.uid(), false)) then
    raise exception 'Only an admin or this build''s project manager can set up its plan.'
      using errcode = '42501';
  end if;
  if exists (select 1 from stages where project_id = p_project) then
    raise exception 'This build already has a plan.';
  end if;
  if not exists (select 1 from workflow_templates where id = p_template) then
    raise exception 'That workflow does not exist.';
  end if;

  perform set_config('buildtrack.plan_rpc', 'on', true);
  update projects set template_id = p_template where id = p_project;
  perform set_config('buildtrack.plan_rpc', 'off', true);

  -- Refuses a template with no stages, or a build with no PM; either way the
  -- template_id written above goes back with it.
  perform public.fn_onboard_project(p_project);
end $$;

grant execute on function public.fn_set_up_plan(uuid, uuid) to authenticated;

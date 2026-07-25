-- Azimuth BuildTrack — project onboarding
-- Called after inserting a project row: generates its stages from the template
-- and backward-schedules everything. Idempotent (won't duplicate stages).

create or replace function public.fn_onboard_project(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_template uuid;
begin
  select template_id into v_template from projects where id = p_project;
  if v_template is null then return; end if;

  insert into stages (project_id, template_stage_id, name, ord, status)
  select p_project, ts.id, ts.name, ts.ord, 'todo'
  from template_stages ts
  where ts.template_id = v_template
    and not exists (select 1 from stages s where s.project_id = p_project);

  perform public.fn_recompute_schedule(p_project);
  perform public.fn_recompute_progress(p_project);
end $$;

-- 0022_project_delays.sql
--
-- Delay attribution for the project dossier. delay_logs already records why a
-- stage slipped (reason, days, note, who logged it), but only per stage — there
-- was no way to see, for a whole build, WHERE it slipped and WHO held that
-- stage. This view joins each delay to its stage + the person logging it + the
-- stage's assignee, so the admin dossier can answer "which stage, who, why, how
-- many days" in one place.
--
-- No new tables — pure read model over existing data.

drop view if exists public.v_project_delays;
create view public.v_project_delays with (security_invoker = on) as
  select
    dl.id,
    s.project_id,
    s.id         as stage_id,
    s.name       as stage_name,
    s.discipline,
    dl.reason_code,
    dl.days_delayed,
    dl.note,
    dl.created_at,
    lg.full_name  as logged_by_name,
    asg.full_name as assignee_name
  from delay_logs dl
  join stages   s   on s.id  = dl.stage_id
  left join profiles lg  on lg.id  = dl.logged_by
  left join profiles asg on asg.id = s.assignee_id;

grant select on public.v_project_delays to authenticated;

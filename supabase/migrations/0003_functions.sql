-- Azimuth BuildTrack — core logic functions

-- ============================================================
-- Backward scheduling (Hero #1): from a project's target_delivery_date,
-- lay out stage planned dates in reverse, then compute each
-- procurement requirement's order_by_date.
-- (MVP: calendar days; holidays/weekends can be layered later.)
-- ============================================================
create or replace function public.fn_recompute_schedule(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_target date;
  v_cursor date;
  r record;
  v_dur int;
begin
  select target_delivery_date into v_target from projects where id = p_project;
  if v_target is null then return; end if;

  v_cursor := v_target;
  -- walk stages from last to first
  for r in
    select s.id, coalesce(ts.default_duration_days, 1) as dur
    from stages s
    left join template_stages ts on ts.id = s.template_stage_id
    where s.project_id = p_project
    order by s.ord desc
  loop
    v_dur := greatest(r.dur, 1);
    update stages
       set planned_end   = v_cursor,
           planned_start = v_cursor - (v_dur - 1)
     where id = r.id;
    v_cursor := (v_cursor - v_dur);  -- day before this stage starts
  end loop;

  -- order-by date for each requirement = needed_by - lead - buffer
  update procurement_requirements pr
     set order_by_date = pr.needed_by_date - ic.lead_time_days - ic.buffer_days
    from item_catalog ic
   where pr.item_catalog_id = ic.id
     and pr.project_id = p_project
     and pr.needed_by_date is not null;
end $$;

-- ============================================================
-- Recompute project % + status from stages
-- ============================================================
create or replace function public.fn_recompute_progress(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_total int; v_done int; v_pct int;
begin
  select count(*), count(*) filter (where status = 'done')
    into v_total, v_done from stages where project_id = p_project;
  v_pct := case when v_total > 0 then round(100.0 * v_done / v_total) else 0 end;
  update projects set progress_pct = v_pct where id = p_project;
end $$;

-- keep progress fresh whenever a stage changes
create or replace function public.trg_stage_progress() returns trigger
language plpgsql as $$
begin
  perform public.fn_recompute_progress(coalesce(new.project_id, old.project_id));
  return null;
end $$;

create trigger t_stage_progress
after insert or update of status or delete on stages
for each row execute function public.trg_stage_progress();

-- ============================================================
-- Requirements that must be ordered soon (drives "To-Order" alerts)
-- ============================================================
create or replace view public.v_order_due as
  select pr.*, ic.name as item_name, p.code as project_code,
         (pr.order_by_date - current_date) as days_left
  from procurement_requirements pr
  join item_catalog ic on ic.id = pr.item_catalog_id
  join projects p on p.id = pr.project_id
  where pr.status = 'pending'
  order by pr.order_by_date asc;

-- ============================================================
-- Recall (Hero #2): every truck that has a given item model installed
-- ============================================================
create or replace function public.fn_recall(p_item uuid)
returns table(project_id uuid, project_code text, serial text, status component_status)
language sql stable as $$
  select ci.installed_in_project_id, p.code, ci.serial_number, ci.status
  from component_instances ci
  join projects p on p.id = ci.installed_in_project_id
  where ci.item_catalog_id = p_item
    and ci.installed_in_project_id is not null;
$$;

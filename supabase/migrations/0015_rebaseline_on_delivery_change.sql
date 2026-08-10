-- 0015_rebaseline_on_delivery_change.sql
--
-- Changing the delivery date re-ran backward scheduling and moved every stage's
-- PLANNED dates, but left the ASSIGNED dates (what the PM committed to in Assign
-- work, shown as "Due …" on the stage) untouched. So after moving delivery
-- earlier, stages could still say they were "Due" *after* the new delivery date
-- — nonsensical, and confusing in testing.
--
-- Fix: a delivery-date change is a full re-plan. fn_recompute_schedule gets an
-- optional p_rebaseline_assigned flag; when true it also snaps each stage's
-- assigned_start/assigned_due to the freshly recomputed planned dates.
--
-- The flag defaults to FALSE so the other callers are unchanged: onboarding and
-- "add/edit material" recompute the plan and order-by dates WITHOUT wiping the
-- PM's per-stage commitments. Only the delivery-date action (setDeliveryDate)
-- passes true. Completed stages (status = 'done') are left alone — their dates
-- are history, not a plan.
--
-- The old 1-arg function is dropped and replaced with a single 2-arg version
-- (new arg defaulted), so every existing call site — the in-SQL
-- `perform public.fn_recompute_schedule(p_project)` calls and the app's 1-arg
-- rpc calls — keeps working and simply gets the default (no rebaseline).

drop function if exists public.fn_recompute_schedule(uuid);

create or replace function public.fn_recompute_schedule(
  p_project uuid,
  p_rebaseline_assigned boolean default false
)
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
  -- walk stages from last to first, laying out planned dates in reverse
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

  -- Full re-plan (delivery date changed): snap the PM's committed dates to the
  -- new plan so a stage is never "Due" after delivery. Completed stages keep
  -- their historical dates.
  if p_rebaseline_assigned then
    update stages
       set assigned_start = planned_start,
           assigned_due   = planned_end
     where project_id = p_project
       and status <> 'done';
  end if;
end $$;

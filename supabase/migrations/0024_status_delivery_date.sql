-- 0024_status_delivery_date.sql
--
-- Bug fix: a build past its promised delivery date kept showing "on track".
--
-- fn_recompute_status only ever looked at per-stage planned_end dates — it never
-- checked the project's own target_delivery_date. So a build whose stages had no
-- planned_end (or a future one) but whose promised delivery date had already
-- passed stayed on_track. Now:
--   • not delivered AND target_delivery_date is in the past  → delayed
--   • not delivered AND delivery is within 7 days with work left → at_risk
-- (the old stage-overrun / order-by / unstarted-stage rules still apply).
--
-- Also re-runs the status of every build once, so existing data corrects itself
-- the moment this migration is applied (rather than waiting for the next edit).

create or replace function public.fn_recompute_status(p_project uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_delivered date; v_target date; v_late int; v_risk int; v_open int; v_status project_status;
begin
  select actual_delivery_date, target_delivery_date into v_delivered, v_target
    from projects where id = p_project;

  if v_delivered is not null then
    v_status := 'delivered';
  else
    -- a stage that isn't done has already blown past its planned end
    select count(*) into v_late from stages
     where project_id = p_project and status <> 'done'
       and planned_end is not null and planned_end < current_date;

    -- the promised delivery date has passed, or a stage overran → delayed
    if (v_target is not null and v_target < current_date) or v_late > 0 then
      v_status := 'delayed';
    else
      -- a stage that should have started hasn't
      select count(*) into v_risk from stages
       where project_id = p_project and status = 'todo'
         and planned_start is not null and planned_start <= current_date;

      -- or a part is past its order-by date and still unordered (Hero #1)
      if v_risk = 0 then
        select count(*) into v_risk from procurement_requirements
         where project_id = p_project and status = 'pending'
           and order_by_date is not null and order_by_date <= current_date;
      end if;

      -- or delivery is a week out (or less) and there's still work left
      if v_risk = 0 and v_target is not null and v_target <= current_date + 7 then
        select count(*) into v_open from stages
         where project_id = p_project and status <> 'done';
        if v_open > 0 then v_risk := 1; end if;
      end if;

      v_status := case when v_risk > 0 then 'at_risk'::project_status
                                       else 'on_track'::project_status end;
    end if;
  end if;

  update projects set status = v_status
   where id = p_project and status is distinct from v_status;
end $$;

-- Correct every existing build now (a build that was silently on_track past its
-- delivery date flips to delayed on deploy, not on the next stage edit).
select public.fn_refresh_all_statuses();

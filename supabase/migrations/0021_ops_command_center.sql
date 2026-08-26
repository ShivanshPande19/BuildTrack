-- 0021_ops_command_center.sql
--
-- The operations backbone the owner asked for — so nobody has to walk the floor
-- asking "which build is where, who's on it, what needs signing first".
--
-- Three things:
--   1. SUB-TEAMS. A department (role) like Workshop is big and splits into teams
--      — Welding, Paint, Electrical, Fitter. Smaller departments (Design) have
--      none. So sub-teams are optional and belong to a department; a person has
--      a department (role) + an optional sub-team.
--   2. A FACTORY BOARD view (v_ops_board) — one row per active build: what stage
--      it's at, which department/sub-team + person is on it, how long it's sat
--      there, its status, and its next order-by date.
--   3. PO APPROVAL PRIORITY. Many POs land at once; the owner should sign the
--      one that unblocks the soonest delivery first. Priority is derived
--      deterministically from the item's order-by date, with an admin override.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. SUB-TEAMS (department → team)
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.sub_teams (
  id         uuid primary key default gen_random_uuid(),
  role       user_role not null,          -- the department this team sits under
  name       text not null,
  created_at timestamptz not null default now(),
  unique (role, name)
);

-- Workshop's teams to start with; other departments add their own as needed.
insert into public.sub_teams (role, name) values
  ('workshop', 'Welding'),
  ('workshop', 'Paint'),
  ('workshop', 'Electrical'),
  ('workshop', 'Fitter')
on conflict (role, name) do nothing;

-- A person's team within their department (optional — Design has none).
alter table public.profiles add column if not exists sub_team_id uuid references sub_teams(id);

alter table public.sub_teams enable row level security;
drop policy if exists sub_teams_read  on public.sub_teams;
drop policy if exists sub_teams_write on public.sub_teams;
create policy sub_teams_read  on public.sub_teams for select using (public.is_staff());
create policy sub_teams_write on public.sub_teams for all
  using (public.is_admin()) with check (public.is_admin());


-- ════════════════════════════════════════════════════════════════════════════
-- 2. PO APPROVAL PRIORITY
-- ════════════════════════════════════════════════════════════════════════════
alter table public.purchase_orders add column if not exists priority_override text
  check (priority_override in ('critical','high','medium','low'));

-- Admin can force a priority (or clear it to fall back to the auto rule).
create or replace function public.fn_set_po_priority(p_po uuid, p_priority text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can change a purchase order''s priority.' using errcode = '42501';
  end if;
  if p_priority is not null and p_priority not in ('critical','high','medium','low') then
    raise exception 'Invalid priority.';
  end if;
  update purchase_orders set priority_override = p_priority where id = p_po;
  perform public.fn_audit('set_po_priority', 'purchase_order', p_po);
end $$;

-- Rebuild the approvals queue with a deterministic priority + a sort rank.
-- Rule (override always wins):
--   overdue (needed_by in the past) → critical
--   needed within 3 days            → high
--   needed within 7 days            → medium
--   needed later                    → low
--   no order-by date (general PO)   → medium
drop view if exists public.v_po_pending_approvals;
create view public.v_po_pending_approvals with (security_invoker = on) as
  select b.*,
         case b.priority when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end as priority_rank
  from (
    select
      po.id, po.po_number, po.approval_status, po.amount,
      po.project_id, po.pm_id, po.vendor_id, po.needed_by, po.priority_override,
      v.name  as vendor_name,
      pr.code as project_code,
      po.submitted_at, po.submitted_by, po.pm_signed_at,
      case when po.approval_status = 'pending_pm'    then po.submitted_at
           when po.approval_status = 'pending_final' then po.pm_signed_at end as waiting_since,
      round(extract(epoch from (now() -
        case when po.approval_status = 'pending_pm'    then po.submitted_at
             when po.approval_status = 'pending_final' then po.pm_signed_at end)) / 3600.0, 1) as waiting_hours,
      (po.needed_by is not null and po.needed_by < current_date) as overdue,
      coalesce(po.priority_override,
        case
          when po.needed_by is null               then 'medium'
          when po.needed_by <  current_date        then 'critical'
          when po.needed_by <= current_date + 3     then 'high'
          when po.needed_by <= current_date + 7     then 'medium'
          else 'low'
        end) as priority
    from purchase_orders po
    left join vendors  v  on v.id  = po.vendor_id
    left join projects pr on pr.id = po.project_id
    where po.approval_status in ('pending_pm','pending_final')
  ) b
  order by priority_rank asc, b.needed_by asc nulls last, b.waiting_since asc nulls last;

grant select on public.v_po_pending_approvals to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. FACTORY BOARD — one row per active build, for the owner's command center
--    security_invoker so the reader's RLS applies (admin/staff see the fleet).
-- ════════════════════════════════════════════════════════════════════════════
drop view if exists public.v_ops_board;
create view public.v_ops_board with (security_invoker = on) as
  select
    p.id as project_id, p.code, p.name, p.status, p.progress_pct,
    p.pm_id, pm.full_name as pm_name,
    p.current_stage_id,
    s.name       as current_stage_name,
    s.discipline as current_discipline,
    s.status     as current_stage_status,
    s.actual_start as stage_started,
    s.planned_end  as stage_planned_end,
    s.assigned_due as stage_due,
    case when s.actual_start is not null then (current_date - s.actual_start) end as days_in_stage,
    a.id        as assignee_id,
    a.full_name as assignee_name,
    a.role      as assignee_role,
    st.id       as sub_team_id,
    st.name     as sub_team_name,
    (select min(rq.order_by_date) from procurement_requirements rq
       where rq.project_id = p.id and rq.status = 'pending') as next_order_by
  from projects p
  left join profiles  pm on pm.id = p.pm_id
  left join stages    s  on s.id  = p.current_stage_id
  left join profiles  a  on a.id  = s.assignee_id
  left join sub_teams st on st.id = a.sub_team_id
  where p.status <> 'delivered';

grant select on public.v_ops_board to authenticated;

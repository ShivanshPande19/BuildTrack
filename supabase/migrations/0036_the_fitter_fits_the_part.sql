-- ============================================================================
-- Migration 0036 — three things the PO → store → install → service walk found
--
--   1. The worker who fits a part can record fitting it.
--   2. A client raises a request on their own truck, as a new request.
--   3. A visit time is told in India time, not UTC.
--   4. A delivered truck is not on the To Order list.
--
-- Idempotent: create or replace, drop policy if exists.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1. fn_install_component — whoever holds work on the stage, and nobody else
--
-- Since 0033 a supervisor holds the Workshop stage and hands its work items
-- ("Equipment fittings", "Plumbing work") to the workers who do them. The
-- caller check still only knew the stage's assignee, so the worker standing at
-- the truck with the part in hand was refused — "Only the member assigned to
-- this stage can install parts into it" — and the supervisor had to scan it
-- for them. Someone holding a work item on the stage may now fit into it.
--
-- And the check had the NULL trap 0026 §4 found in fn_reopen_ticket: on a
-- stage with no assignee, `v_assignee = auth.uid()` is NULL, the OR comes out
-- NULL, `if not NULL` is false, and the guard let anyone through. coalesce,
-- for the same reason as there.
--
-- Body is 0029's otherwise, unchanged.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_install_component(p_component uuid, p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_project  uuid; v_assignee uuid; v_cstatus component_status;
  v_serial   text; v_code text; v_sstatus stage_status;
  v_reserved uuid; v_rcode text;
begin
  select s.project_id, s.assignee_id, s.status, p.code
    into v_project, v_assignee, v_sstatus, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not coalesce(
       public.is_admin()
    or v_assignee = auth.uid()
    or public.has_role(array['store'])
    or exists (select 1 from stage_tasks
                where stage_id = p_stage and assignee_id = auth.uid())
  , false) then
    raise exception 'Only the people working on this stage can install parts into it.' using errcode = '42501';
  end if;

  -- An approved stage is closed. fn_start_stage and fn_submit_stage have both
  -- refused one since 0026; this did not, so a part could be added to the
  -- record of a stage the PM had already signed off — and the truck record and
  -- the client's build timeline both changed after the approval.
  if v_sstatus = 'done' then
    raise exception 'That stage is already approved as complete — a part cannot be added to it now.';
  end if;

  select status, serial_number, installed_in_project_id
    into v_cstatus, v_serial, v_reserved
    from component_instances where id = p_component;
  if v_cstatus is null then raise exception 'That component is not in the system — ask Store to log it first.'; end if;
  if v_cstatus <> 'in_stock' then
    raise exception 'Serial % is marked % — only in-stock parts can be installed.', coalesce(v_serial, '?'), v_cstatus;
  end if;

  -- An in-stock part that already names a build is Store's earmark for that
  -- build (0026: intake reserves, it does not install). Fitting it elsewhere
  -- used to overwrite the earmark silently, so the build it was bought for
  -- lost its part and nobody was told.
  if v_reserved is not null and v_reserved <> v_project then
    select code into v_rcode from projects where id = v_reserved;
    raise exception 'Serial % is reserved for % — ask Store to release it before fitting it to %.',
      coalesce(v_serial, '?'), coalesce(v_rcode, 'another build'), v_code;
  end if;

  update component_instances
     set status = 'installed',
         installed_in_project_id = v_project,
         installed_stage_id      = p_stage,
         installed_by            = auth.uid(),
         install_date            = current_date
   where id = p_component;

  perform public.fn_audit('install_component', 'component_instance', p_component);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. A client's request is about their own truck, and starts as a request
--
-- p_tickets_client_new (0002) checked only `raised_by = auth.uid()`. So a
-- client could insert a ticket against any build id — another customer's
-- truck — and every service member was notified about it (t_ticket_created).
-- And since the row was theirs to write, they could also insert it already
-- resolved, or already assigned to a technician of their choosing.
--
-- The app's "Raise a request" sends project, category, description, priority
-- and status 'open'; that is all a client may set. The ticket number, SLA and
-- raiser are filled in by trg_ticket_defaults.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists p_tickets_client_new on tickets;
create policy p_tickets_client_new on tickets for insert with check (
  raised_by = auth.uid()
  and exists (select 1 from projects p
               where p.id = tickets.project_id
                 and p.client_account_id = public.my_client_account())
  and status = 'open'
  and assigned_to is null
  and linked_component_id is null
  and resolution_type is null
  and resolution_note is null
  and resolved_at is null
  and closed_at is null
  and first_reply_at is null
);


-- ════════════════════════════════════════════════════════════════════════════
-- 3. fn_schedule_visit — the time in the message is the time in Pune
--
-- to_char on a timestamptz formats it in the session's time zone, which on
-- Supabase is UTC. A visit booked for 11:00 in the app reached the client as
-- "will visit on 26 Oct at 05:30 AM", and the technician got the same wrong
-- hour. Every Azimuth customer and technician is in India.
--
-- Body is 0010's, with `p_when at time zone 'Asia/Kolkata'` in the three
-- to_char calls and nothing else changed.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_schedule_visit(
  p_ticket uuid, p_technician uuid, p_when timestamptz, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_num text; v_project uuid; v_code text; v_role user_role; v_status ticket_status; v_tech text;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can schedule a visit.' using errcode = '42501';
  end if;
  if p_technician is null then raise exception 'Pick a technician for the visit.'; end if;
  if p_when is null then raise exception 'Pick a date and time for the visit.'; end if;

  select t.ticket_number, t.project_id, t.status, p.code
    into v_num, v_project, v_status, v_code
    from tickets t left join projects p on p.id = t.project_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status in ('resolved', 'closed') then
    raise exception 'This ticket is already %.', v_status;
  end if;

  select role, coalesce(full_name, email) into v_role, v_tech
    from profiles where id = p_technician;
  if v_role is null then raise exception 'That technician does not exist.'; end if;
  if v_role not in ('service', 'workshop') then
    raise exception 'Only service or workshop members can be sent on a visit (that member is %).', v_role;
  end if;

  -- One live booking per ticket: re-scheduling replaces the open one.
  update service_visits set status = 'cancelled'
   where ticket_id = p_ticket and status = 'scheduled';

  insert into service_visits (ticket_id, technician_id, scheduled_date, status, note, created_by)
  values (p_ticket, p_technician, p_when, 'scheduled', nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_id;

  update tickets
     set assigned_to = coalesce(assigned_to, p_technician),
         status = case when status = 'open' then 'in_progress'::ticket_status else status end,
         first_reply_at = coalesce(first_reply_at, now())
   where id = p_ticket;

  perform public.fn_notify(p_technician, 'visit',
    'Visit booked · ' || coalesce(v_code, 'truck'),
    'You are scheduled for ' || to_char(p_when at time zone 'Asia/Kolkata', 'DD Mon, HH12:MI AM') || ' on ' || v_num || '.',
    'ticket', p_ticket);

  perform public.fn_notify_client(v_project, 'visit',
    'Service visit confirmed',
    coalesce(v_tech, 'A technician') || ' will visit on ' || to_char(p_when at time zone 'Asia/Kolkata', 'DD Mon') ||
    ' at ' || to_char(p_when at time zone 'Asia/Kolkata', 'HH12:MI AM') || '.');

  perform public.fn_audit('schedule_visit', 'ticket', p_ticket);
  return v_id;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. v_order_due — nothing is ordered for a truck the customer already has
--
-- A build marked delivered with requirements still pending (fn_mark_delivered
-- p_force, or a requirement nobody ordered because it was not needed) kept
-- them on Procurement's To Order list and Admin's order alerts — for ever,
-- since nothing closes them. Delivered builds drop out here.
--
-- 0003's view with that one condition added. security_invoker restated: a
-- replaced view keeps its options, but 0009 §14 is the reason it is set and
-- it should not depend on that.
-- ════════════════════════════════════════════════════════════════════════════

create or replace view public.v_order_due with (security_invoker = on) as
  select pr.*, ic.name as item_name, p.code as project_code,
         (pr.order_by_date - current_date) as days_left
  from procurement_requirements pr
  join item_catalog ic on ic.id = pr.item_catalog_id
  join projects p on p.id = pr.project_id
  where pr.status = 'pending'
    and p.status <> 'delivered'
  order by pr.order_by_date asc;

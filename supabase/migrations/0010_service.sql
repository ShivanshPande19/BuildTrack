-- ============================================================================
-- 0010_service.sql — Service role (post-delivery support)
--
-- The tables for after-sales existed since 0001 but nothing ever used them:
-- tickets had no SLA and no consumer, service_visits was never written, and no
-- truck could even reach 'delivered' because nothing set actual_delivery_date.
-- This wires the whole after-sales loop:
--
--   PM      marks a build delivered  ──►  it enters service
--   Client  raises a request         ──►  every service member is notified
--   Service triages, assigns a technician, schedules a visit
--   Service resolves (warranty replace / repair / remote guide)  ──►  client told
--
-- Same architecture as 0009: rules live here as SECURITY DEFINER RPCs so they
-- hold no matter what calls them. Safe to re-run (idempotent).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1. SCHEMA — the few columns the after-sales loop was missing
-- ════════════════════════════════════════════════════════════════════════════

-- Ticket numbers were generated in Dart ('R-<millis>'), so they were neither
-- stable nor sequential. A sequence makes them predictable: T-001, T-002 …
create sequence if not exists ticket_number_seq start 1;

alter table tickets add column if not exists closed_at    timestamptz;
alter table tickets add column if not exists first_reply_at timestamptz;

-- A visit needs a note (what to bring / what was found) and an audit trail.
alter table service_visits add column if not exists note       text;
alter table service_visits add column if not exists created_at timestamptz not null default now();
alter table service_visits add column if not exists created_by uuid references profiles(id) on delete set null;

create index if not exists idx_tickets_status   on tickets(status, sla_due);
create index if not exists idx_tickets_project  on tickets(project_id);
create index if not exists idx_tickets_assignee on tickets(assigned_to);
create index if not exists idx_visits_ticket    on service_visits(ticket_id);
create index if not exists idx_comp_warranty    on component_instances(warranty_end);


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Notify a whole role (the missing piece that left client tickets unheard)
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_notify_role(
  p_roles text[], p_type text, p_title text,
  p_body text default null, p_entity_type text default null, p_entity_id uuid default null,
  p_exclude uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select id from profiles
     where role::text = any(p_roles)
       and status <> 'disabled'
       and (p_exclude is null or id <> p_exclude)
  loop
    perform public.fn_notify(r.id, p_type, p_title, p_body, p_entity_type, p_entity_id);
    n := n + 1;
  end loop;
  return n;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. SLA — every ticket gets a deadline the moment it is raised
--    high = 4h · medium = 24h · low = 72h
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_sla_hours(p_priority ticket_priority)
returns int language sql immutable as $$
  select case p_priority when 'high' then 4 when 'medium' then 24 else 72 end
$$;

-- Fills in the ticket number and the SLA deadline for *any* insert path — the
-- client's "Raise a request" screen and Service's own "New ticket" alike.
create or replace function public.trg_ticket_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ticket_number is null or btrim(new.ticket_number) = '' then
    new.ticket_number := 'T-' || lpad(nextval('ticket_number_seq')::text, 3, '0');
  end if;
  if new.sla_due is null then
    new.sla_due := now() + (public.fn_sla_hours(new.priority) || ' hours')::interval;
  end if;
  if new.raised_by is null then
    new.raised_by := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists t_ticket_defaults on tickets;
create trigger t_ticket_defaults before insert on tickets
  for each row execute function public.trg_ticket_defaults();

-- ticket_number is NOT NULL, so the trigger has to be able to fill it in.
alter table tickets alter column ticket_number drop not null;

-- A client request that nobody is told about is the same as no request at all.
create or replace function public.trg_ticket_created() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_client text;
begin
  select p.code, ca.business_name into v_code, v_client
    from projects p
    left join client_accounts ca on ca.id = p.client_account_id
   where p.id = new.project_id;

  perform public.fn_notify_role(
    array['service', 'admin'],
    'ticket',
    'New ' || new.priority || '-priority request · ' || coalesce(v_code, 'truck'),
    coalesce(nullif(btrim(coalesce(new.description, '')), ''), new.category::text)
      || coalesce(' — ' || v_client, ''),
    'ticket', new.id,
    new.raised_by);          -- don't notify whoever raised it
  return new;
end $$;

drop trigger if exists t_ticket_created on tickets;
create trigger t_ticket_created after insert on tickets
  for each row execute function public.trg_ticket_created();


-- ════════════════════════════════════════════════════════════════════════════
-- 4. A build enters service only once it is delivered
--    Nothing set actual_delivery_date, so no project could ever reach
--    'delivered' and the Service role had nothing to work with.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_mark_delivered(
  p_project uuid, p_date date default null, p_force boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_code text; v_name text; v_open int; v_delivered date;
begin
  select pm_id, code, name, actual_delivery_date
    into v_pm, v_code, v_name, v_delivered
    from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only this build''s project manager can mark it delivered.' using errcode = '42501';
  end if;
  if v_delivered is not null then
    raise exception 'This build was already delivered on %.', to_char(v_delivered, 'DD Mon YYYY');
  end if;

  select count(*) into v_open from stages
   where project_id = p_project and status <> 'done';
  if v_open > 0 and not p_force then
    raise exception '% stage(s) are still not approved as done. Finish them, or confirm to deliver anyway.', v_open;
  end if;

  update projects
     set actual_delivery_date = coalesce(p_date, current_date)
   where id = p_project;

  perform public.fn_recompute_progress(p_project);   -- flips status to 'delivered'

  perform public.fn_notify_client(p_project, 'delivered',
    v_name || ' is delivered',
    'Your truck is on the road. Any issue from here — raise a request in the app and our service team will pick it up.');

  perform public.fn_notify_role(array['service'], 'delivered',
    v_code || ' is now in service',
    v_name || ' has been delivered and is under warranty support.', 'project', p_project);

  perform public.fn_audit('mark_delivered', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. Service actions
-- ════════════════════════════════════════════════════════════════════════════

-- Service raising a ticket on the client's behalf (phone call, site visit…).
create or replace function public.fn_create_ticket(
  p_project uuid, p_category ticket_category, p_description text,
  p_priority ticket_priority default 'medium', p_component uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can raise a ticket on a client''s behalf.' using errcode = '42501';
  end if;
  if p_project is null then raise exception 'Pick the truck this request is about.'; end if;
  if nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Describe the issue before saving.';
  end if;

  insert into tickets (project_id, category, description, priority, linked_component_id,
                       raised_by, status)
  values (p_project, p_category, btrim(p_description), p_priority, p_component,
          auth.uid(), 'open')
  returning id into v_id;

  return v_id;
end $$;

-- Triage: put a ticket on a technician's plate.
create or replace function public.fn_assign_ticket(p_ticket uuid, p_technician uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_code text; v_role user_role; v_pstatus user_status; v_old uuid; v_status ticket_status;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can assign a ticket.' using errcode = '42501';
  end if;

  select t.ticket_number, t.assigned_to, t.status, p.code
    into v_num, v_old, v_status, v_code
    from tickets t left join projects p on p.id = t.project_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status in ('resolved', 'closed') then
    raise exception 'This ticket is already %.', v_status;
  end if;

  if p_technician is not null then
    select role, status into v_role, v_pstatus from profiles where id = p_technician;
    if v_role is null then raise exception 'That member does not exist.'; end if;
    if v_role not in ('service', 'workshop') then
      raise exception 'Tickets can only go to service or workshop members (that member is %).', v_role;
    end if;
    if v_pstatus = 'disabled' then raise exception 'That member''s account is disabled.'; end if;
  end if;

  update tickets
     set assigned_to = p_technician,
         status = case when p_technician is not null and status = 'open' then 'in_progress'::ticket_status
                       else status end,
         first_reply_at = coalesce(first_reply_at, now())
   where id = p_ticket;

  if p_technician is not null and p_technician is distinct from v_old then
    perform public.fn_notify(p_technician, 'ticket',
      v_num || ' assigned to you',
      'A support request on ' || coalesce(v_code, 'a truck') || ' is now yours.',
      'ticket', p_ticket);
  end if;

  perform public.fn_audit('assign_ticket', 'ticket', p_ticket);
end $$;

-- Book a technician visit. Also moves the ticket to in_progress and tells the client.
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
    'You are scheduled for ' || to_char(p_when, 'DD Mon, HH12:MI AM') || ' on ' || v_num || '.',
    'ticket', p_ticket);

  perform public.fn_notify_client(v_project, 'visit',
    'Service visit confirmed',
    coalesce(v_tech, 'A technician') || ' will visit on ' || to_char(p_when, 'DD Mon') ||
    ' at ' || to_char(p_when, 'HH12:MI AM') || '.');

  perform public.fn_audit('schedule_visit', 'ticket', p_ticket);
  return v_id;
end $$;

-- Close the loop: how it was fixed, and tell the client.
create or replace function public.fn_resolve_ticket(
  p_ticket uuid, p_resolution resolution_type, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_project uuid; v_status ticket_status; v_raised uuid; v_note text; v_contact uuid;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can resolve a ticket.' using errcode = '42501';
  end if;

  select t.ticket_number, t.project_id, t.status, t.raised_by, ca.contact_user_id
    into v_num, v_project, v_status, v_raised, v_contact
    from tickets t
    left join projects p        on p.id  = t.project_id
    left join client_accounts ca on ca.id = p.client_account_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status in ('resolved', 'closed') then
    raise exception 'This ticket is already %.', v_status;
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');
  if v_note is null then
    raise exception 'Add a short note on what was done — the client sees this.';
  end if;

  update tickets
     set status = 'resolved', resolution_type = p_resolution, resolution_note = v_note,
         resolved_at = now(), first_reply_at = coalesce(first_reply_at, now())
   where id = p_ticket;

  -- a booked visit that happened is done, not still pending
  update service_visits set status = 'done'
   where ticket_id = p_ticket and status = 'scheduled';

  perform public.fn_notify_client(v_project, 'resolved',
    v_num || ' resolved',
    v_note);
  -- The raiser may be someone other than the client contact (e.g. a service
  -- member who logged a phoned-in issue) — tell them too, but never send the
  -- client the same notice twice.
  if v_raised is not null
     and v_raised <> auth.uid()
     and v_raised is distinct from v_contact then
    perform public.fn_notify(v_raised, 'resolved', v_num || ' resolved', v_note, 'ticket', p_ticket);
  end if;

  perform public.fn_audit('resolve_ticket', 'ticket', p_ticket);
end $$;

create or replace function public.fn_close_ticket(p_ticket uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status ticket_status;
begin
  if not public.has_role(array['admin', 'service']) then
    raise exception 'Only the service team can close a ticket.' using errcode = '42501';
  end if;
  select status into v_status from tickets where id = p_ticket;
  if v_status is null then raise exception 'Ticket not found.'; end if;
  if v_status = 'closed' then return; end if;
  if v_status <> 'resolved' then
    raise exception 'Resolve the ticket before closing it.';
  end if;
  update tickets set status = 'closed', closed_at = now() where id = p_ticket;
  perform public.fn_audit('close_ticket', 'ticket', p_ticket);
end $$;

-- Client says it isn't actually fixed.
create or replace function public.fn_reopen_ticket(p_ticket uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_status ticket_status; v_assignee uuid; v_reason text;
begin
  select ticket_number, status, assigned_to into v_num, v_status, v_assignee
    from tickets where id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;
  if v_status not in ('resolved', 'closed') then
    raise exception 'This ticket is still open.';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  update tickets
     set status = 'in_progress', resolved_at = null, closed_at = null,
         priority = 'high',                       -- a repeat visit jumps the queue
         sla_due = now() + (public.fn_sla_hours('high') || ' hours')::interval
   where id = p_ticket;

  perform public.fn_notify_role(array['service', 'admin'], 'ticket',
    v_num || ' reopened',
    coalesce(v_reason, 'The issue is not resolved.'), 'ticket', p_ticket, auth.uid());
  perform public.fn_notify(v_assignee, 'ticket', v_num || ' reopened',
    coalesce(v_reason, 'The issue is not resolved.'), 'ticket', p_ticket);

  perform public.fn_audit('reopen_ticket', 'ticket', p_ticket);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. Warranty lookup — search a serial / model / truck and see what's covered
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_warranty_search(p_q text default null)
returns table (
  component_id   uuid,
  item_name      text,
  model          text,
  serial         text,
  project_id     uuid,
  project_code   text,
  vendor_name    text,
  warranty_end   date,
  days_left      int,
  comp_status    text
) language sql stable security definer set search_path = public as $$
  select ci.id,
         coalesce(ic.name, 'Component'),
         coalesce(ic.model, ''),
         coalesce(ci.serial_number, '—'),
         ci.installed_in_project_id,
         coalesce(p.code, ''),
         coalesce(v.name, ''),
         ci.warranty_end,
         case when ci.warranty_end is null then null
              else (ci.warranty_end - current_date) end::int,
         ci.status::text
    from component_instances ci
    left join item_catalog ic on ic.id = ci.item_catalog_id
    left join projects     p  on p.id  = ci.installed_in_project_id
    left join vendors      v  on v.id  = ci.vendor_id
   where public.is_staff()
     and (
       p_q is null or btrim(p_q) = ''
       or ci.serial_number ilike '%' || btrim(p_q) || '%'
       or ic.name          ilike '%' || btrim(p_q) || '%'
       or ic.model         ilike '%' || btrim(p_q) || '%'
       or p.code           ilike '%' || btrim(p_q) || '%'
       or p.name           ilike '%' || btrim(p_q) || '%'
     )
   order by ci.warranty_end nulls last, ci.serial_number
   limit 100
$$;

-- Warranties running out in the next 60 days, newest expiry first — drives the
-- "warranty ending" flag on the delivered-trucks list.
create or replace function public.fn_warranty_expiring(p_days int default 60)
returns table (project_id uuid, project_code text, expiring int, soonest date)
language sql stable security definer set search_path = public as $$
  select ci.installed_in_project_id, coalesce(p.code, ''),
         count(*)::int, min(ci.warranty_end)
    from component_instances ci
    join projects p on p.id = ci.installed_in_project_id
   where public.is_staff()
     and ci.status = 'installed'
     and ci.warranty_end is not null
     and ci.warranty_end between current_date and current_date + p_days
   group by 1, 2
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7. RLS — the client must be able to see how their own request was handled
-- ════════════════════════════════════════════════════════════════════════════

-- Service visits: staff read (0009), admin/service write (0009). A client needs
-- to see the visit booked for their own ticket.
drop policy if exists p_visits_client on service_visits;
create policy p_visits_client on service_visits for select using (
  exists (
    select 1 from tickets t
     where t.id = service_visits.ticket_id
       and t.raised_by = auth.uid()));

-- Let the client reopen their own ticket via fn_reopen_ticket (definer, so no
-- table grant is needed) — but they must not be able to edit tickets directly.
-- 0009's p_tickets_client (select own) and p_tickets_client_new (insert own) stand.


-- ════════════════════════════════════════════════════════════════════════════
-- 8. Backfill — give existing tickets the SLA/number they never had
-- ════════════════════════════════════════════════════════════════════════════

update tickets
   set sla_due = created_at + (public.fn_sla_hours(priority) || ' hours')::interval
 where sla_due is null;

update tickets
   set ticket_number = 'T-' || lpad(nextval('ticket_number_seq')::text, 3, '0')
 where ticket_number is null or btrim(ticket_number) = '';

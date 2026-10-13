-- 0026_demo_hardening.sql
--
-- The audit pass before the demo found a set of real defects in the functions
-- the two hero features depend on, plus a handful of rules that were still only
-- enforced in the UI. This closes them in one migration. No schema additions
-- beyond one policy change and a FK sweep; everything here is idempotent and
-- safe to re-run.
--
--  1. fn_recompute_schedule — a delivery-date change left every material's
--     needed-by (and therefore its order-by alert) on the OLD plan, and never
--     refreshed the build's status. Hero #1 went stale the moment a PM pushed
--     a date.
--  2. fn_resubmit_po — wiped notes / ship-to / payment terms, and dropped a
--     vendor or delivery-date change entirely when the lines weren't resent.
--  3. fn_receive_po — read the PO status without a row lock, so two taps
--     doubled the stock and wrote two GRNs.
--  4. fn_reopen_ticket — had no caller check at all: any signed-in user could
--     reopen any ticket and force it to high priority.
--  5. trg_guard_stages — didn't guard status / actual_*, so an assignee could
--     mark their own stage done with a direct UPDATE, skipping submit+approve.
--  6. fn_notify* / fn_audit were callable by anyone over RPC (spoofed
--     notifications). Revoked from `authenticated`.
--  7. Store couldn't create a catalogue item, so its own "new item" sheets
--     failed on RLS.
--  8. An invited member could never become 'active' — the set-password screen's
--     own update was blocked by RLS.
--  9. Submitting a design told the client nothing; the "they've been notified"
--     banner was untrue. fn_create_design / fn_add_design_version now notify.
-- 10. Offboarding a member failed on the seven FKs added after 0009's sweep.
-- 11. A fresh / demo database had no essential items, so Store's "request from
--     procurement" picker was empty.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. BACKWARD SCHEDULING — a delivery-date change is a full re-plan (Hero #1)
--
-- procurement_requirements.needed_by_date was written once, at onboarding, from
-- the stage's planned_start at that moment. Nothing ever moved it again, and
-- order_by_date is derived FROM it — so after "Log delay + push the delivery
-- date" every material still alerted against the old schedule, v_order_due
-- showed a wrong "order in N days", and fn_recompute_status kept forcing the
-- build to at_risk off a stale order_by_date.
--
-- On a rebaseline (the delivery-date path) each still-pending requirement is
-- re-pointed at its own stage's new planned_start before order-by is recomputed.
-- Requirements that are already ordered or received are history and are left
-- alone, as are requirements with no stage to anchor to (added by hand by the
-- PM) — those keep whatever needed-by the PM set.
--
-- The function also ends by refreshing the project's status. planned_* changes
-- don't fire t_stage_progress (it's `after update of status`), so a build kept
-- showing 'delayed' after its date was pushed until some screen happened to
-- call fn_refresh_all_statuses.
-- ════════════════════════════════════════════════════════════════════════════

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

  -- Full re-plan (delivery date changed): snap the PM's committed dates to the
  -- new plan so a stage is never "Due" after delivery. Completed stages keep
  -- their historical dates.
  if p_rebaseline_assigned then
    update stages
       set assigned_start = planned_start,
           assigned_due   = planned_end
     where project_id = p_project
       and status <> 'done';

    -- …and move each still-pending material's needed-by onto the new plan, so
    -- the order-by engine alerts against the schedule that is actually live.
    -- Anchored on the stage the requirement's item belongs to in the template
    -- BOM; a requirement with no such anchor keeps the PM's own needed-by.
    update procurement_requirements pr
       set needed_by_date = anchor.planned_start
      from (
        select tsi.item_catalog_id, min(s.planned_start) as planned_start
          from template_stage_items tsi
          join stages s on s.template_stage_id = tsi.template_stage_id
                       and s.project_id = p_project
         where s.planned_start is not null
         group by tsi.item_catalog_id
      ) anchor
     where pr.project_id      = p_project
       and pr.status          = 'pending'
       and pr.item_catalog_id = anchor.item_catalog_id
       and pr.needed_by_date is distinct from anchor.planned_start;
  end if;

  -- order-by date for each requirement = needed_by - lead - buffer
  update procurement_requirements pr
     set order_by_date = pr.needed_by_date - ic.lead_time_days - ic.buffer_days
    from item_catalog ic
   where pr.item_catalog_id = ic.id
     and pr.project_id = p_project
     and pr.needed_by_date is not null;

  -- The plan moved, so on-track / at-risk / delayed may have moved with it.
  perform public.fn_recompute_status(p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. fn_resubmit_po — stop losing the fields the caller didn't resend
--
-- Two defects:
--   • vendor_id / delivery_date used coalesce(arg, existing), but
--     payment_terms / notes / ship_to used nullif(btrim(coalesce(arg,''))',''),
--     so a null argument ERASED the stored value. The app's resubmit never
--     sends notes or ship-to, so both were nulled on every resubmit.
--   • The whole header UPDATE sat inside `if p_lines is not null`, so a
--     resubmit that changed only the vendor or the delivery date was silently
--     discarded.
--
-- Now: the header always updates, and every optional text field keeps its
-- current value when the argument is null. Passing an empty string still
-- clears a field deliberately.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_resubmit_po(
  p_po            uuid,
  p_vendor        uuid    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default null,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_appr po_approval_status; v_sub uuid; v_project uuid; v_pm uuid; v_num text; v_next po_approval_status;
  v_subtotal numeric := 0; v_tax numeric := 0; v_line jsonb; v_qty int; v_price numeric; v_rate numeric; v_lt numeric;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can resubmit a purchase order.' using errcode = '42501';
  end if;

  select approval_status, submitted_by, project_id, po_number into v_appr, v_sub, v_project, v_num
    from purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_appr <> 'rejected' then
    raise exception 'Only a rejected purchase order can be resubmitted.';
  end if;

  if v_project is not null then
    select pm_id into v_pm from projects where id = v_project;
  end if;
  v_next := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Replace the lines + recompute the totals only when a new set is supplied.
  if p_lines is not null then
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_qty   := coalesce((v_line->>'qty')::int, 1);
      v_price := coalesce((v_line->>'unit_price')::numeric, 0);
      v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
      v_lt    := v_qty * v_price;
      v_subtotal := v_subtotal + v_lt;
      v_tax      := v_tax + (v_lt * v_rate / 100.0);
    end loop;

    delete from po_lines where po_id = p_po;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
      values (
        p_po,
        (v_line->>'item_catalog_id')::uuid,
        coalesce((v_line->>'qty')::int, 1),
        coalesce((v_line->>'unit_price')::numeric, 0),
        coalesce((v_line->>'tax_rate')::numeric, 0),
        nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
        nullif(btrim(coalesce(v_line->>'description', '')), ''));
    end loop;

    update purchase_orders
       set subtotal = v_subtotal, tax_total = v_tax, amount = v_subtotal + v_tax
     where id = p_po;
  end if;

  -- Header + wipe the signatures and re-enter the chain from the top. Every
  -- optional field keeps its current value when the caller passes null.
  update purchase_orders
     set vendor_id       = coalesce(p_vendor, vendor_id),
         delivery_date   = coalesce(p_delivery_date, delivery_date),
         payment_terms   = case when p_payment_terms is null then payment_terms
                                else nullif(btrim(p_payment_terms), '') end,
         notes           = case when p_notes is null then notes
                                else nullif(btrim(p_notes), '') end,
         ship_to         = case when p_ship_to is null then ship_to
                                else nullif(btrim(p_ship_to), '') end,
         approval_status = v_next, pm_id = v_pm,
         pm_signed_by = null, pm_signed_at = null,
         final_signed_by = null, final_signed_at = null,
         rejected_by = null, rejected_at = null, rejection_reason = null,
         submitted_by = auth.uid(), submitted_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (p_po, 'resubmitted', 'rejected', v_next, auth.uid());

  if v_next = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' was revised — please sign',
      'Procurement addressed the feedback and resubmitted this purchase order.',
      'purchase_order', p_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' was revised — needs approval',
      'A rejected purchase order has been revised and resubmitted.',
      'purchase_order', p_po, auth.uid());
  end if;

  perform public.fn_audit('resubmit_po', 'purchase_order', p_po);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. fn_receive_po — lock the row before reading its status
--
-- Two people (or two taps) receiving the same PO both read status='dispatched',
-- both passed the guard, and both added the quantities: stock doubled and two
-- GRNs were written. `for update` makes the second caller wait and then see
-- 'received', so it raises instead. Body otherwise identical to 0018.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  -- Serialise concurrent receives of the same PO.
  select status into v_status from purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;
  if v_status not in ('dispatched', 'partial') then
    raise exception 'Mark the purchase order dispatched before receiving it.';
  end if;

  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Bulk items only: a serialized item enters stock when Store logs its serial,
  -- so topping up stock_items here would double-count it.
  for r in
    select pl.item_catalog_id, sum(pl.qty)::numeric as q
      from po_lines pl
      join item_catalog ic on ic.id = pl.item_catalog_id
     where pl.po_id = p_po and ic.serialized = false
     group by pl.item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;
  update stock_requests          set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. fn_reopen_ticket — who may reopen
--
-- It had no caller check whatsoever, and it forces priority to 'high' and
-- resets the SLA clock. Any signed-in user could jump any ticket to the front
-- of the service queue. Now: the client the ticket belongs to, the service
-- team, or an admin.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_reopen_ticket(p_ticket uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num text; v_status ticket_status; v_assignee uuid; v_reason text;
        v_raised uuid; v_ca uuid;
begin
  select t.ticket_number, t.status, t.assigned_to, t.raised_by, p.client_account_id
    into v_num, v_status, v_assignee, v_raised, v_ca
    from tickets t left join projects p on p.id = t.project_id
   where t.id = p_ticket;
  if v_num is null then raise exception 'Ticket not found.'; end if;

  -- The client whose truck it is (or who raised it), service, or an admin.
  --
  -- coalesce, and not for tidiness: `v_ca = public.my_client_account()` is NULL
  -- for any staff member (they have no client account), so the whole OR came out
  -- NULL rather than false — and `if not NULL then` is *false*, so the guard did
  -- not fire and an unrelated welder could reopen anyone's ticket. Exactly the
  -- same trap as `is_admin()` in §14, which is why both are spelled out.
  if not coalesce(
       public.has_role(array['admin','service'])
    or v_raised = auth.uid()
    or (v_ca is not null and v_ca = public.my_client_account())
  , false) then
    raise exception 'Only the client this request belongs to, or the service team, can reopen it.'
      using errcode = '42501';
  end if;

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
-- 5. trg_guard_stages — an assignee may not mark their own stage done
--
-- The guard listed assignment and schedule columns but not `status` or
-- `actual_*`, so the assignee (who legitimately has UPDATE on their own stage,
-- for the checklist) could set status='done' with a direct write and skip the
-- whole submit → approve chain. Progress and the client's view would say the
-- stage was approved when no PM had seen it.
--
-- The sanctioned transitions all run through SECURITY DEFINER RPCs
-- (fn_start_stage, fn_submit_stage, fn_decide_stage). Those triggers still fire
-- with the caller's auth.uid(), so each RPC marks the transaction as a
-- sanctioned one and the guard stands aside. Anything else — a direct UPDATE
-- from a client library — is refused.
-- ════════════════════════════════════════════════════════════════════════════

-- Marks the current transaction as a sanctioned stage transition. `true` makes
-- the setting transaction-local, so it can never leak into the next statement
-- on a pooled connection.
create or replace function public.fn_stage_rpc_begin() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('buildtrack.stage_rpc', 'on', true);
end $$;

create or replace function public.trg_guard_stages() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid;
begin
  -- No JWT = service role / SQL editor / cron / seed.
  if auth.uid() is null then return new; end if;

  -- Inside one of the sanctioned stage RPCs.
  if coalesce(current_setting('buildtrack.stage_rpc', true), '') = 'on' then
    return new;
  end if;

  select pm_id into v_pm from projects where id = new.project_id;
  if public.is_admin() or v_pm = auth.uid() then return new; end if;

  if new.assignee_id   is distinct from old.assignee_id
     or new.discipline is distinct from old.discipline
     or new.ord        is distinct from old.ord
     or new.project_id is distinct from old.project_id
     or new.bay_id     is distinct from old.bay_id
     or new.planned_start is distinct from old.planned_start
     or new.planned_end   is distinct from old.planned_end
     or new.assigned_due   is distinct from old.assigned_due
     or new.assigned_start is distinct from old.assigned_start then
    raise exception 'Only the project manager can change a stage''s assignment or schedule.'
      using errcode = '42501';
  end if;

  -- A stage moves forward through Start / Submit / Approve, never by hand.
  if new.status       is distinct from old.status
     or new.actual_start is distinct from old.actual_start
     or new.actual_end   is distinct from old.actual_end then
    raise exception 'Use Start work and Submit for approval to move this stage — it cannot be set directly.'
      using errcode = '42501';
  end if;

  return new;
end $$;

drop trigger if exists t_guard_stages on stages;
create trigger t_guard_stages before update on stages
  for each row execute function public.trg_guard_stages();


-- The three sanctioned transitions, each re-declared to open the guard first.
-- Bodies are otherwise unchanged from 0009.

create or replace function public.fn_start_stage(p_stage uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_assignee uuid; v_project uuid; v_pm uuid; v_status stage_status; v_stage text; v_code text;
begin
  select s.assignee_id, s.project_id, s.status, s.name, p.pm_id, p.code
    into v_assignee, v_project, v_status, v_stage, v_pm, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid() or v_pm = auth.uid()) then
    raise exception 'Only the member assigned to this stage can start it.' using errcode = '42501';
  end if;
  if v_status = 'done' then
    raise exception 'This stage is already approved as complete.';
  end if;
  if v_status = 'in_progress' then return; end if;

  perform public.fn_stage_rpc_begin();
  update stages
     set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
   where id = p_stage;

  perform public.fn_notify(v_pm, 'stage_started',
    v_code || ' · ' || v_stage || ' started',
    'Work has begun on this stage.', 'stage', p_stage);
end $$;


create or replace function public.fn_submit_stage(p_stage uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_assignee uuid; v_project uuid; v_pm uuid; v_status stage_status;
        v_stage text; v_code text; v_id uuid; v_me text;
begin
  select s.assignee_id, s.project_id, s.status, s.name, p.pm_id, p.code
    into v_assignee, v_project, v_status, v_stage, v_pm, v_code
    from stages s join projects p on p.id = s.project_id
   where s.id = p_stage;
  if v_project is null then raise exception 'Stage not found.'; end if;

  if not (public.is_admin() or v_assignee = auth.uid()) then
    raise exception 'Only the member assigned to this stage can submit it.' using errcode = '42501';
  end if;
  if v_status = 'done' then
    raise exception 'This stage is already approved as complete.';
  end if;
  if v_pm is null then
    raise exception 'This build has no project manager yet — ask an admin to assign one before submitting.';
  end if;
  if exists (select 1 from stage_approvals where stage_id = p_stage and status = 'pending') then
    raise exception 'This stage is already waiting for approval.';
  end if;

  insert into stage_approvals (stage_id, submitted_by, approver_id, status)
  values (p_stage, auth.uid(), v_pm, 'pending')
  returning id into v_id;

  if v_status = 'todo' then
    perform public.fn_stage_rpc_begin();
    update stages set status = 'in_progress',
                      actual_start = coalesce(actual_start, current_date)
     where id = p_stage;
  end if;

  select coalesce(full_name, email) into v_me from profiles where id = auth.uid();
  perform public.fn_notify(v_pm, 'stage_submitted',
    v_code || ' · ' || v_stage || ' needs approval',
    coalesce(v_me, 'A team member') || ' marked this stage complete.', 'stage', p_stage);

  return v_id;
end $$;


create or replace function public.fn_decide_stage(
  p_approval uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_stage uuid; v_project uuid; v_pm uuid; v_sub uuid; v_astatus approval_status;
  v_stage_name text; v_code text; v_pname text; v_ord int;
  v_next uuid; v_next_name text; v_next_assignee uuid;
begin
  select a.stage_id, a.submitted_by, a.status, s.project_id, s.name, s.ord, p.pm_id, p.code, p.name
    into v_stage, v_sub, v_astatus, v_project, v_stage_name, v_ord, v_pm, v_code, v_pname
    from stage_approvals a
    join stages   s on s.id = a.stage_id
    join projects p on p.id = s.project_id
   where a.id = p_approval
     for no key update of a;
  if v_stage is null then raise exception 'Approval not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only this build''s project manager can decide this submission.' using errcode = '42501';
  end if;
  if v_astatus <> 'pending' then
    raise exception 'This submission has already been decided.';
  end if;

  update stage_approvals
     set status = case when p_approve then 'approved'::approval_status
                                      else 'rejected'::approval_status end,
         note = nullif(btrim(coalesce(p_note, '')), ''),
         decided_at = now()
   where id = p_approval;

  perform public.fn_stage_rpc_begin();

  if p_approve then
    update stages set status = 'done', actual_end = coalesce(actual_end, current_date)
     where id = v_stage;

    select id, name, assignee_id into v_next, v_next_name, v_next_assignee
      from stages
     where project_id = v_project and status = 'todo' and ord > v_ord
     order by ord limit 1;

    if v_next is not null then
      update stages set status = 'in_progress', actual_start = coalesce(actual_start, current_date)
       where id = v_next;
      perform public.fn_notify(v_next_assignee, 'stage_assigned',
        v_code || ' · ' || v_next_name || ' is up next',
        'The previous stage was approved — this one is now in progress.', 'stage', v_next);
    end if;

    perform public.fn_notify(v_sub, 'approved',
      v_code || ' · ' || v_stage_name || ' approved',
      'Your work was approved. Nice one.', 'stage', v_stage);

    perform public.fn_notify_client(v_project, 'stage_done',
      v_pname || ': ' || v_stage_name || ' complete',
      'Another stage of your build is finished. Open the app to see the latest.');
  else
    update stages set status = 'rework' where id = v_stage;
    perform public.fn_notify(v_sub, 'rework',
      v_code || ' · ' || v_stage_name || ' sent back',
      coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Your project manager asked for changes on this stage.'),
      'stage', v_stage);
  end if;

  perform public.fn_recompute_progress(v_project);
  perform public.fn_audit(case when p_approve then 'approve_stage' else 'reject_stage' end, 'stage', v_stage);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. The definer helpers are not a public API
--
-- fn_notify / fn_notify_client / fn_notify_role / fn_audit run as the table
-- owner and were granted to `authenticated` by default, so any signed-in user
-- could POST to /rpc/fn_notify and plant a notification in anyone's feed, or
-- write a false audit entry. They are only ever called from inside other
-- functions, which keep working: a SECURITY DEFINER function's body runs as its
-- owner, not as the caller.
--
-- fn_recompute_schedule / fn_refresh_all_statuses stay granted — the app calls
-- both directly. fn_stage_rpc_begin (§5) is revoked here for the same reason.
--
-- The role list is read from pg_roles, because `anon` exists on Supabase but
-- not on the plain Postgres the test suite runs against. (That suite also
-- re-grants everything to `authenticated` afterwards so the RLS tests can run
-- as real users, so this hardening is only observable on a real project.)
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare
  r record;
  v_roles text := 'public';
begin
  select v_roles || coalesce(string_agg(', ' || quote_ident(rolname), ''), '')
    into v_roles
    from pg_roles where rolname in ('authenticated', 'anon');

  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fn_notify','fn_notify_client','fn_notify_role','fn_audit',
                         'fn_stage_rpc_begin')
  loop
    execute format('revoke all on function %s from %s', r.sig, v_roles);
  end loop;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 7. Store may create a catalogue item
--
-- Store logs parts at intake and keeps the inventory, so it hits "this item
-- isn't in the catalogue" more than anyone. item_catalog writes were
-- {admin,procurement,pm}, so Store's inline "new item" sheets (Stock → request,
-- Log component) failed on RLS with a permission error.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists item_catalog_write on public.item_catalog;
create policy item_catalog_write on public.item_catalog for all
  using      (public.has_role(array['admin','procurement','pm','store']))
  with check (public.has_role(array['admin','procurement','pm','store']));


-- ════════════════════════════════════════════════════════════════════════════
-- 8. A member owns their own name, phone and activation
--
-- profiles writes were admin-only, which broke two things:
--   • the set-password screen's `profiles.update(status:'active')` was silently
--     discarded (RLS filters the row out rather than erroring), so every
--     invited member stayed 'invited' forever — which reads as "never logged
--     in" on the Team screen;
--   • Settings → Account details had nothing it could save, which is why it was
--     a "coming soon" placeholder.
--
-- So: you may update your OWN row. Which columns is enforced by the trigger
-- below rather than by the policy, because a WITH CHECK can only see the new
-- row — it cannot tell which columns changed. Role, email, status-beyond-
-- activation, created_by and sub_team stay the admin's, so this can never be
-- used to self-promote.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists p_profiles_activate_self on public.profiles;
drop policy if exists p_profiles_update_self on public.profiles;
create policy p_profiles_update_self on public.profiles for update
  using      (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.trg_profiles_self_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.id is distinct from old.id then
    raise exception 'A profile id cannot change.' using errcode = '42501';
  end if;
  if new.id <> auth.uid() then return new; end if;   -- not the self-service path

  -- Yours to edit: full_name, phone, avatar_color — plus accepting the invite.
  if new.role        is distinct from old.role
     or new.email       is distinct from old.email
     or new.created_by  is distinct from old.created_by
     or new.sub_team_id is distinct from old.sub_team_id then
    raise exception 'Only an admin can change your role, email or team.' using errcode = '42501';
  end if;
  -- Status: invited → active only. Nobody re-enables their own disabled login.
  if new.status is distinct from old.status
     and not (old.status = 'invited' and new.status = 'active') then
    raise exception 'Only an admin can change your account status.' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_profiles_self_update on public.profiles;
create trigger t_profiles_self_update before update on public.profiles
  for each row execute function public.trg_profiles_self_update();


-- ════════════════════════════════════════════════════════════════════════════
-- 9. Design submission actually reaches the client
--
-- The app created an artifact and its first version with three separate client
-- writes (not atomic — a failure halfway left an artifact with no version and
-- no current_version_id), and nothing notified the client, while the screen
-- said "they've been notified". fn_create_design does the whole thing in one
-- transaction and notifies the client and the PM when it is submitted;
-- fn_add_design_version (0025) now notifies too.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_create_design(
  p_project     uuid,
  p_type        design_type,
  p_model_url   text    default null,
  p_image_url   text    default null,
  p_change_note text    default null,
  p_submit      boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_artifact uuid; v_version uuid; v_code text; v_pname text; v_pm uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can create a design.' using errcode = '42501';
  end if;

  select code, name, pm_id into v_code, v_pname, v_pm from projects where id = p_project;
  if v_code is null then raise exception 'Build not found.'; end if;

  insert into design_artifacts (project_id, type, status, created_by)
  values (p_project, p_type,
          (case when p_submit then 'pending_approval' else 'draft' end)::design_status,
          auth.uid())
  returning id into v_artifact;

  insert into design_versions (artifact_id, version_no, model_url, file_url, change_note)
  values (v_artifact, 1, nullif(p_model_url, ''), nullif(p_image_url, ''), nullif(p_change_note, ''))
  returning id into v_version;

  update design_artifacts set current_version_id = v_version where id = v_artifact;

  if p_submit then
    perform public.fn_notify_client(p_project, 'design_submitted',
      'A new design is ready for your approval',
      'The design team has shared the ' || p_type || ' design for ' || v_pname ||
      '. Open the app to approve it or ask for changes.');
    perform public.fn_notify(v_pm, 'design_submitted',
      v_code || ' · ' || p_type || ' design sent to the client',
      'The design team submitted it for client approval.', 'design', v_artifact);
  end if;

  perform public.fn_audit('create_design', 'design_artifact', v_artifact);
  return v_artifact;
end $$;


create or replace function public.fn_add_design_version(
  p_artifact    uuid,
  p_model_url   text default null,
  p_image_url   text default null,
  p_change_note text default null,
  p_submit      boolean default false)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_next int; v_id uuid; v_project uuid; v_type design_type;
  v_code text; v_pname text; v_pm uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can add a design version.' using errcode = '42501';
  end if;

  -- Lock the artifact row so concurrent version inserts for the SAME artifact
  -- serialise instead of colliding on version_no.
  select a.project_id, a.type into v_project, v_type
    from design_artifacts a where a.id = p_artifact for update;
  if not found then
    raise exception 'Design not found.';
  end if;

  select coalesce(max(version_no), 0) + 1 into v_next
    from design_versions where artifact_id = p_artifact;

  insert into design_versions (artifact_id, version_no, model_url, file_url, change_note)
    values (p_artifact, v_next, nullif(p_model_url, ''), nullif(p_image_url, ''), nullif(p_change_note, ''))
    returning id into v_id;

  update design_artifacts
     set current_version_id = v_id,
         status = (case when p_submit then 'pending_approval' else 'draft' end)::design_status,
         client_feedback = null
   where id = p_artifact;

  if p_submit then
    select code, name, pm_id into v_code, v_pname, v_pm from projects where id = v_project;
    perform public.fn_notify_client(v_project, 'design_submitted',
      'A revised design is ready for your approval',
      'The design team has shared version ' || v_next || ' of the ' || v_type ||
      ' design for ' || v_pname || '. Open the app to approve it or ask for changes.');
    perform public.fn_notify(v_pm, 'design_submitted',
      v_code || ' · ' || v_type || ' design v' || v_next || ' sent to the client',
      'The design team submitted a revision for client approval.', 'design', p_artifact);
  end if;

  return v_id;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 10. Offboarding a member must never fail on a foreign key
--
-- 0009 swept every FK pointing at profiles and made it ON DELETE SET NULL, but
-- 0017 and 0020 added seven more afterwards (purchase_orders.{pm_id,
-- submitted_by, pm_signed_by, final_signed_by, rejected_by},
-- po_approval_events.actor_id, stock_requests.requested_by). Removing a member
-- who had raised or signed a PO failed with a foreign-key violation. Same sweep,
-- re-run, so it also covers anything added later.
-- ════════════════════════════════════════════════════════════════════════════

do $$
declare r record; v_notnull boolean;
begin
  for r in
    select con.conname,
           con.conrelid::regclass::text as tbl,
           att.attname                  as col
      from pg_constraint con
      join pg_class     rel on rel.oid = con.conrelid
      join pg_namespace ns  on ns.oid  = rel.relnamespace
      join unnest(con.conkey) as k(attnum) on true
      join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
     where con.contype   = 'f'
       and ns.nspname    = 'public'
       and con.confrelid = 'public.profiles'::regclass
       and con.confdeltype = 'a'                    -- still NO ACTION
       and array_length(con.conkey, 1) = 1
  loop
    select attnotnull into v_notnull
      from pg_attribute where attrelid = r.tbl::regclass and attname = r.col;
    if v_notnull then continue; end if;             -- e.g. notifications.user_id (cascades already)

    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I foreign key (%I) '
                   'references public.profiles(id) on delete set null',
                   r.tbl, r.conname, r.col);
  end loop;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 11. An existing database has essentials
--
-- 0019 marks every bulk (non-serialized) item as a general essential, but it
-- only sweeps the rows that exist when it runs — so a database whose catalogue
-- was filled in afterwards has none, and Store's "request from procurement"
-- picker (which only offers essentials) is empty. This catches that up, and
-- only when NOTHING is essential yet, so it never clobbers a deliberate choice.
--
-- It cannot fix a *fresh* database: the migration chain finishes before seed.sql
-- runs, so this sweeps an empty table. The seed sets `is_essential` on its own
-- rows instead — see the comment there.
-- ════════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (select 1 from public.item_catalog where is_essential) then
    update public.item_catalog set is_essential = true where serialized = false;
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 12. A purchase order closes the demand it actually covers
--
-- fn_create_po only parked the ONE requirement passed as p_requirement, and only
-- the hero card on the To-Order list passes it. A PO raised from the blank "New
-- PO" button covered the same materials but left their requirements `pending`,
-- so the order-by alert kept firing for something already ordered — and
-- fn_recompute_status kept the build at_risk off that stale alert. Procurement
-- was being nagged to re-order what was on its way.
--
-- Now: after the lines are written, every still-pending requirement on this PO's
-- project whose item is on this PO is parked against it. The explicit
-- p_requirement still works and is still linked first (it also carries the
-- order-by deadline onto the PO), so nothing about the hero path changes.
-- A general (no-project) PO has no requirements to close, and fn_reject_po's
-- rework loop keeps them parked, exactly as before.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_create_po(
  p_vendor        uuid    default null,
  p_project       uuid    default null,
  p_order_date    date    default null,
  p_delivery_date date    default null,
  p_lines         jsonb   default '[]'::jsonb,
  p_notes         text    default null,
  p_payment_terms text    default null,
  p_ship_to       text    default null,
  p_requirement   uuid    default null,
  p_stock_request uuid    default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_po       uuid;
  v_num      text;
  v_pm       uuid;
  v_appr     po_approval_status;
  v_needed   date;
  v_subtotal numeric := 0;
  v_tax      numeric := 0;
  v_line     jsonb;
  v_qty      int;
  v_price    numeric;
  v_rate     numeric;
  v_lt       numeric;
  v_linked   int := 0;
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can raise a purchase order.' using errcode = '42501';
  end if;

  -- Route: a project PO needs the PM's signature first; a general PO does not.
  if p_project is not null then
    select pm_id into v_pm from projects where id = p_project;
  end if;
  v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Carry the order-by deadline through for delay flagging / priority.
  if p_requirement is not null then
    select order_by_date into v_needed from procurement_requirements where id = p_requirement;
  end if;

  -- Sum the lines up front for the header totals.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_qty   := coalesce((v_line->>'qty')::int, 1);
    v_price := coalesce((v_line->>'unit_price')::numeric, 0);
    v_rate  := coalesce((v_line->>'tax_rate')::numeric, 0);
    v_lt    := v_qty * v_price;
    v_subtotal := v_subtotal + v_lt;
    v_tax      := v_tax + (v_lt * v_rate / 100.0);
  end loop;

  v_num := 'PO-' || to_char(nextval('public.po_number_seq'), 'FM00000');

  insert into purchase_orders (
    po_number, vendor_id, project_id, status, approval_status,
    order_date, delivery_date, needed_by, ship_to, payment_terms, notes,
    subtotal, tax_total, amount, pm_id, submitted_by, submitted_at, created_by)
  values (
    v_num, p_vendor, p_project, 'ordered', v_appr,
    coalesce(p_order_date, current_date), p_delivery_date, v_needed,
    nullif(btrim(coalesce(p_ship_to, '')), ''),
    nullif(btrim(coalesce(p_payment_terms, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''),
    v_subtotal, v_tax, v_subtotal + v_tax, v_pm, auth.uid(), now(), auth.uid())
  returning id into v_po;

  -- Lines.
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    insert into po_lines (po_id, item_catalog_id, qty, unit_price, tax_rate, hsn_code, description)
    values (
      v_po,
      (v_line->>'item_catalog_id')::uuid,
      coalesce((v_line->>'qty')::int, 1),
      coalesce((v_line->>'unit_price')::numeric, 0),
      coalesce((v_line->>'tax_rate')::numeric, 0),
      nullif(btrim(coalesce(v_line->>'hsn_code', '')), ''),
      nullif(btrim(coalesce(v_line->>'description', '')), ''));
  end loop;

  -- Park the demand this PO fulfils so it leaves the To-Order list. If the PO
  -- is later rejected, fn_reject_po puts it back.
  if p_requirement is not null then
    update procurement_requirements set status = 'ordered', po_id = v_po where id = p_requirement;
  end if;
  if p_stock_request is not null then
    update stock_requests set status = 'ordered', po_id = v_po where id = p_stock_request;
  end if;

  -- …and the rest of the demand this PO actually covers, named by its lines.
  if p_project is not null then
    update procurement_requirements pr
       set status = 'ordered', po_id = v_po
     where pr.project_id = p_project
       and pr.status = 'pending'
       and pr.po_id is null
       and exists (select 1 from po_lines pl
                    where pl.po_id = v_po and pl.item_catalog_id = pr.item_catalog_id);
    get diagnostics v_linked = row_count;
    -- Closing an alert can take the build off at_risk.
    if v_linked > 0 or p_requirement is not null then
      perform public.fn_recompute_status(p_project);
    end if;
  end if;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id)
  values (v_po, 'created', null, v_appr, auth.uid());

  -- Notify the next signer.
  if v_appr = 'pending_pm' then
    perform public.fn_notify(v_pm, 'po_approval',
      v_num || ' needs your signature',
      'Procurement raised a purchase order on your build — review and sign it.',
      'purchase_order', v_po);
  else
    perform public.fn_notify_role(array['admin'], 'po_approval',
      v_num || ' needs final approval',
      'A purchase order is awaiting final sign-off.',
      'purchase_order', v_po, auth.uid());
  end if;

  perform public.fn_audit('create_po', 'purchase_order', v_po);
  return v_po;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 13. Handing a build to a new PM hands over the work in flight
--
-- `stage_approvals.approver_id` and `purchase_orders.pm_id` are snapshots taken
-- when the work was submitted. Reassigning a build left them pointing at the
-- old PM, so: the new PM's approvals queue was empty while the team waited, the
-- old PM (who no longer owns the build, and may have left) still held the
-- signature, and `fn_pm_sign_po` refused the new PM because `pm_id` wasn't them.
-- A PO only came unstuck if procurement happened to resubmit it.
--
-- So reassignment now moves the open items with the build. Decided approvals and
-- signed-off POs are history and are left exactly as they are — the trail must
-- keep saying who actually signed.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.fn_assign_pm(p_project uuid, p_pm uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old uuid; v_code text; v_name text; v_role user_role; v_pstatus user_status;
  v_stages int := 0; v_pos int := 0;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can assign a project manager.' using errcode = '42501';
  end if;
  if p_pm is null then
    raise exception 'A build must always have a project manager.';
  end if;

  select pm_id, code, name into v_old, v_code, v_name from projects where id = p_project;
  if not found then raise exception 'Project not found.'; end if;

  select role, status into v_role, v_pstatus from profiles where id = p_pm;
  if v_role is null then
    raise exception 'That member does not exist.';
  end if;
  if v_role <> 'pm' then
    raise exception 'Projects can only be assigned to a Project Manager (that member is %).', v_role;
  end if;
  if v_pstatus = 'disabled' then
    raise exception 'That project manager''s account is disabled.';
  end if;

  if v_old is not distinct from p_pm then return; end if;   -- nothing to do

  update projects
     set pm_id = p_pm, pm_assigned_by = auth.uid(), pm_assigned_at = now()
   where id = p_project;

  -- Work in flight moves to the new PM.
  update stage_approvals a
     set approver_id = p_pm
    from stages s
   where s.id = a.stage_id
     and s.project_id = p_project
     and a.status = 'pending';
  get diagnostics v_stages = row_count;

  update purchase_orders
     set pm_id = p_pm
   where project_id = p_project
     and approval_status in ('pending_pm','pending_final','rejected');
  get diagnostics v_pos = row_count;

  perform public.fn_notify(p_pm, 'project_assigned',
    v_code || ' is now yours',
    'You have been assigned as project manager for ' || v_name || '.' ||
    case when v_stages > 0 or v_pos > 0
      then ' Waiting on you: ' ||
           concat_ws(' and ',
             nullif(v_stages, 0) || ' stage approval(s)',
             nullif(v_pos, 0) || ' purchase order(s)') || '.'
      else ' Assign its stages to get the build moving.' end,
    'project', p_project);

  if v_old is not null then
    perform public.fn_notify(v_old, 'project_reassigned',
      v_code || ' was reassigned',
      v_name || ' now has a different project manager.', 'project', p_project);
  end if;

  perform public.fn_audit('assign_pm', 'project', p_project);
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 14. A disabled account can read nothing
--
-- `profiles.status` was set and shown but never enforced: `my_role()` returned
-- the role regardless, so `is_staff()` / `has_role()` / `is_admin()` all said
-- yes and a disabled member who still had a valid session (or simply knew their
-- password — the auth user is untouched) could carry on using their role's
-- screens. Offboarding someone was a label, not a revocation.
--
-- Returning NULL for a disabled account makes every role test fail, which in
-- turn makes every RLS policy that depends on one deny. The app signs such a
-- user out at login with an explanation rather than dropping them into an empty
-- shell.
--
-- `invited` is deliberately still allowed: that is the state between the invite
-- and the password being set, and the set-password screen has to work.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.my_role() returns user_role
  language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() and status <> 'disabled' $$;

-- is_admin() must be strictly true/false, not three-valued.
--
-- `my_role()` can return NULL — now for a disabled account, and always for a
-- caller with no profile — and `select NULL = 'admin'` is NULL. RLS reads NULL
-- as false, so the policies were fine. plpgsql does not: `if not NULL then` is
-- *false*, so every `if not public.is_admin() then raise` guard in the RPCs was
-- silently skipped for a NULL role. A disabled admin walked straight through it,
-- and so did any caller with no JWT at all — which, since these functions are
-- SECURITY DEFINER and granted to PUBLIC, meant an anonymous POST to
-- /rpc/fn_assign_pm could reassign a build. coalesce closes both.
-- is_staff() and has_role() already coalesce, so nothing else changes.
--
-- **Behaviour change worth knowing:** fn_assign_pm, fn_onboard_project,
-- fn_final_approve_po and fn_set_po_priority now refuse a caller with no JWT —
-- so running them by hand in the Supabase SQL editor raises "Only an admin…".
-- Everything else (fn_recompute_schedule, fn_refresh_all_statuses, the daily
-- cron, the seed, the guard triggers' `auth.uid() is null` escape) is unaffected.
create or replace function public.is_admin() returns boolean
  language sql stable as $$ select coalesce(public.my_role() = 'admin', false) $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 15. Correct every build's status now, so the fixes above are visible without
--     waiting for the next edit or the daily cron.
-- ════════════════════════════════════════════════════════════════════════════

select public.fn_refresh_all_statuses();

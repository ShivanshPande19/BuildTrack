-- 0027_po_needs_a_pm.sql
--
-- A purchase order on a build whose project manager has gone silently skipped
-- the PM's signature.
--
-- The routing rule is:
--
--     v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;
--
-- which reads "a general PO has no PM, so it goes straight to the owner" — and
-- that is right. What it also does, unintentionally, is treat *a project PO
-- whose build has no PM* as a general PO. One approval step disappears and
-- nothing says so: the PO lands in the owner's queue looking exactly like a
-- stock order, and the build's own manager never sees that money was committed
-- against their truck.
--
-- A build is supposed to always have a PM — `fn_onboard_project` refuses to
-- create one without it — but `profiles` carries `ON DELETE SET NULL` on
-- `projects.pm_id` (0009, so that offboarding a person can never fail on a
-- foreign key). So offboarding a PM leaves their builds PM-less, and from then
-- on every PO raised against them quietly loses a signature.
--
-- Both paths that route a PO now refuse instead, naming the fix. That strands
-- the PO until an admin assigns a PM — which is the correct outcome, because
-- the build is already stranded: its stages cannot be assigned or approved
-- either (`fn_submit_stage` has refused PM-less builds since 0009, with the
-- same reasoning and nearly the same sentence).
--
-- Idempotent: two function replacements, nothing else.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. Raising a PO
--
-- Body is 0026's, with the guard added after the PM lookup. Everything else —
-- totals, numbering, the requirement auto-link, the notifications — is
-- unchanged.
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
  v_code     text;
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
    select pm_id, code into v_pm, v_code from projects where id = p_project;
    if v_code is null then
      raise exception 'That build does not exist.';
    end if;
    -- A build with no PM cannot take a PO: there is nobody to sign the first
    -- step, and routing it straight to the owner would drop that step without
    -- saying so.
    if v_pm is null then
      raise exception 'Build % has no project manager yet — ask an admin to assign one before raising a purchase order against it.', v_code;
    end if;
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
-- 2. Resubmitting a rejected PO
--
-- Same hole on the way back round: a PO raised while the build had a PM, whose
-- PM was then offboarded, would re-enter the chain at the owner. Same refusal,
-- for the same reason. Body is 0026's otherwise.
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
  v_appr po_approval_status; v_sub uuid; v_project uuid; v_pm uuid; v_num text;
  v_code text; v_next po_approval_status;
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
    select pm_id, code into v_pm, v_code from projects where id = v_project;
    if v_pm is null then
      raise exception 'Build % has no project manager yet — ask an admin to assign one before resubmitting this purchase order.', coalesce(v_code, '?');
    end if;
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

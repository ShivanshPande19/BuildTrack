-- 0020_po_approvals.sql
--
-- Multi-level Purchase Order approval + delay tracking, and the data an
-- office-level PO document needs (rates, tax, HSN, buyer/vendor identity).
--
-- The real-world flow the business runs:
--
--   Procurement raises the PO (with clarity from the PM)
--        └─► PM signs it            (level 1 — only for project POs)
--              └─► Final approver signs  (level 2 — a company owner/admin)
--                    └─► order is actually placed  →  ordered → dispatched → received
--
-- General / stock POs (wheels, sheets, metal — no project, no PM) skip the PM
-- step and go straight to the final approver.
--
-- Until now a PO was a bare INSERT that went live as 'ordered' the instant
-- Procurement created it — nobody signed anything, and there was no record of
-- who held it up when an order slipped because a signature was late. This
-- migration adds:
--   • a separate APPROVAL lifecycle (pending_pm → pending_final → approved /
--     rejected) that gates the existing FULFILMENT lifecycle (ordered →
--     dispatched → received). A PO cannot be dispatched or received until it is
--     approved (enforced by a trigger, not just the UI).
--   • po_approval_events — an immutable, timestamped trail of every signature /
--     rejection, so "the order was late because Puneet was travelling" is a
--     fact on the record, not a guess. This is the delay log for approvals.
--   • money + tax + HSN on the lines, buyer identity (company_settings) and
--     vendor GSTIN/address, so a proper PO document can be generated (0020 only
--     captures the data; the PDF is rendered in the app).
--
-- Reuses the existing po_status / req_status enums untouched.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. APPROVAL STATUS ENUM
-- ════════════════════════════════════════════════════════════════════════════
do $$ begin
  if not exists (select 1 from pg_type where typname = 'po_approval_status') then
    create type po_approval_status as enum ('pending_pm','pending_final','approved','rejected');
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. SCHEMA — approval fields + money + document identity
-- ════════════════════════════════════════════════════════════════════════════

-- Buyer identity for the top of a PO document (single row).
create table if not exists public.company_settings (
  id         uuid primary key default gen_random_uuid(),
  only_one   boolean not null default true unique,   -- enforces a single row
  name       text not null default 'Azimuth Business on Wheels',
  address    text,
  gstin      text,
  state      text,
  phone      text,
  email      text,
  logo_url   text,
  updated_at timestamptz not null default now()
);
insert into public.company_settings (only_one) values (true) on conflict (only_one) do nothing;

-- Vendor (supplier) identity for the PO document.
alter table public.vendors add column if not exists gstin   text;
alter table public.vendors add column if not exists address text;
alter table public.vendors add column if not exists state   text;
alter table public.vendors add column if not exists email   text;

-- Catalog: HSN/SAC code + an optional default rate to pre-fill a new PO line.
alter table public.item_catalog add column if not exists hsn_code     text;
alter table public.item_catalog add column if not exists default_rate numeric;

-- Line-level money: rate, GST %, HSN + a free-text description override.
alter table public.po_lines add column if not exists unit_price  numeric not null default 0;
alter table public.po_lines add column if not exists tax_rate    numeric not null default 0;  -- GST %
alter table public.po_lines add column if not exists hsn_code    text;
alter table public.po_lines add column if not exists description text;

-- Purchase order: approval lifecycle + the signatures + totals + doc fields.
alter table public.purchase_orders add column if not exists approval_status po_approval_status not null default 'pending_pm';
alter table public.purchase_orders add column if not exists subtotal        numeric not null default 0;
alter table public.purchase_orders add column if not exists tax_total       numeric not null default 0;
alter table public.purchase_orders add column if not exists amount          numeric not null default 0;  -- grand total
alter table public.purchase_orders add column if not exists needed_by       date;                        -- order-by deadline (for delay flagging)
alter table public.purchase_orders add column if not exists delivery_date   date;                        -- promised delivery on the document
alter table public.purchase_orders add column if not exists ship_to         text;
alter table public.purchase_orders add column if not exists payment_terms   text;
alter table public.purchase_orders add column if not exists notes           text;
alter table public.purchase_orders add column if not exists pm_id           uuid references profiles(id);
alter table public.purchase_orders add column if not exists submitted_by    uuid references profiles(id);
alter table public.purchase_orders add column if not exists submitted_at    timestamptz;
alter table public.purchase_orders add column if not exists pm_signed_by    uuid references profiles(id);
alter table public.purchase_orders add column if not exists pm_signed_at    timestamptz;
alter table public.purchase_orders add column if not exists final_signed_by uuid references profiles(id);
alter table public.purchase_orders add column if not exists final_signed_at timestamptz;
alter table public.purchase_orders add column if not exists rejected_by     uuid references profiles(id);
alter table public.purchase_orders add column if not exists rejected_at     timestamptz;
alter table public.purchase_orders add column if not exists rejection_reason text;

create index if not exists idx_po_approval on public.purchase_orders (approval_status);
create index if not exists idx_po_pm       on public.purchase_orders (pm_id);

-- Immutable trail of every approval event (the delay log for approvals).
create table if not exists public.po_approval_events (
  id          uuid primary key default gen_random_uuid(),
  po_id       uuid not null references purchase_orders(id) on delete cascade,
  event       text not null,                       -- created | pm_signed | final_signed | rejected
  from_status po_approval_status,
  to_status   po_approval_status,
  actor_id    uuid references profiles(id),
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists po_appr_events_po_idx on public.po_approval_events (po_id, created_at);

-- Sequential, human-friendly PO numbers (PO-00001…) generated server-side, the
-- same way tickets get T-001. The old client-side 'PO-<millis>' scheme could
-- collide and carried no ordering. The distinct zero-padded format won't clash
-- with any pre-existing 'PO-<millis>' rows.
create sequence if not exists public.po_number_seq;

-- Existing POs were already placed with the vendor, so they are effectively
-- approved — grandfather them in. Guarded on submitted_at (which every PO
-- raised through fn_create_po sets) so this is safe to re-run and never
-- auto-approves a genuinely pending PO.
update public.purchase_orders
   set approval_status = 'approved'
 where approval_status = 'pending_pm'
   and submitted_at is null;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. GUARD — a PO cannot be dispatched or received until it is approved
--    (defence in depth: the UI hides the action, this makes it impossible)
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.trg_po_require_approval() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status
     and new.status in ('dispatched','partial','received')
     and new.approval_status <> 'approved' then
    raise exception 'This purchase order must be fully approved before it can be dispatched or received.'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_po_require_approval on public.purchase_orders;
create trigger trg_po_require_approval
  before update on public.purchase_orders
  for each row execute function public.trg_po_require_approval();


-- ════════════════════════════════════════════════════════════════════════════
-- 4. FUNCTIONS
-- ════════════════════════════════════════════════════════════════════════════

-- Raise a PO. Procurement (or admin) only. Computes totals from the lines,
-- routes it to the PM (project PO) or straight to final approval (general PO),
-- optionally links + parks the requirement / stock request it fulfils, and
-- notifies the next signer.
--
-- p_lines is a jsonb array of:
--   { "item_catalog_id": uuid, "qty": int, "unit_price": numeric,
--     "tax_rate": numeric, "hsn_code": text, "description": text }
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
begin
  if not public.has_role(array['admin','procurement']) then
    raise exception 'Only procurement or an admin can raise a purchase order.' using errcode = '42501';
  end if;

  -- Route: a project PO needs the PM's signature first; a general PO does not.
  if p_project is not null then
    select pm_id into v_pm from projects where id = p_project;
  end if;
  v_appr := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Carry the order-by deadline through for delay flagging.
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


-- PM signs a project PO (level 1). Moves it to the final approver.
create or replace function public.fn_pm_sign_po(p_po uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_appr po_approval_status; v_num text;
begin
  select pm_id, approval_status, po_number into v_pm, v_appr, v_num
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;

  if not (public.is_admin() or v_pm = auth.uid()) then
    raise exception 'Only the build''s project manager (or an admin) can sign this purchase order.'
      using errcode = '42501';
  end if;
  if v_appr <> 'pending_pm' then
    raise exception 'This purchase order is not awaiting a project manager''s signature.';
  end if;

  update purchase_orders
     set approval_status = 'pending_final', pm_signed_by = auth.uid(), pm_signed_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id, note)
  values (p_po, 'pm_signed', 'pending_pm', 'pending_final', auth.uid(),
          nullif(btrim(coalesce(p_note, '')), ''));

  perform public.fn_notify_role(array['admin'], 'po_approval',
    v_num || ' needs final approval',
    'Signed by the project manager — awaiting final sign-off.',
    'purchase_order', p_po, auth.uid());

  perform public.fn_audit('pm_sign_po', 'purchase_order', p_po);
end $$;


-- Final approver (admin / owner) signs off (level 2). The order is now placed.
create or replace function public.fn_final_approve_po(p_po uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_appr po_approval_status; v_num text; v_sub uuid; v_pm uuid;
begin
  select approval_status, po_number, submitted_by, pm_id into v_appr, v_num, v_sub, v_pm
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;

  if not public.is_admin() then
    raise exception 'Only a company owner / admin can give final approval.' using errcode = '42501';
  end if;
  if v_appr <> 'pending_final' then
    raise exception 'This purchase order is not awaiting final approval.';
  end if;

  update purchase_orders
     set approval_status = 'approved', final_signed_by = auth.uid(), final_signed_at = now()
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id, note)
  values (p_po, 'final_signed', 'pending_final', 'approved', auth.uid(),
          nullif(btrim(coalesce(p_note, '')), ''));

  -- Tell whoever raised it (and the PM) that the order is live.
  perform public.fn_notify(v_sub, 'po_approved',
    v_num || ' approved',
    'Final approval is in — you can place the order with the vendor.',
    'purchase_order', p_po);
  if v_pm is not null and v_pm <> coalesce(v_sub, '00000000-0000-0000-0000-000000000000') then
    perform public.fn_notify(v_pm, 'po_approved',
      v_num || ' approved', 'The purchase order on your build has been approved.',
      'purchase_order', p_po);
  end if;

  perform public.fn_audit('approve_po', 'purchase_order', p_po);
end $$;


-- Reject at either step, with a mandatory reason. This is a rework loop, not a
-- dead end: the PO goes back to whoever raised it (with the remark) so they can
-- fix and resubmit it (fn_resubmit_po). The requirement it fulfils stays parked
-- against it — the PO is being reworked, not abandoned.
--   • Whoever rejects, procurement (the raiser) is put on the hook to fix it.
--   • When the *admin* rejects, the PM is also told — they had signed it, and
--     their signature is undone (a resubmit will come back to them).
create or replace function public.fn_reject_po(p_po uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_appr po_approval_status; v_num text; v_sub uuid; v_admin_rejected boolean;
begin
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required to reject a purchase order.';
  end if;

  select pm_id, approval_status, po_number, submitted_by into v_pm, v_appr, v_num, v_sub
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;

  if v_appr not in ('pending_pm','pending_final') then
    raise exception 'Only a purchase order still awaiting approval can be rejected.';
  end if;
  -- Admin can reject at any step; the PM only their own build's PM step.
  if not (public.is_admin() or (v_appr = 'pending_pm' and v_pm = auth.uid())) then
    raise exception 'You are not allowed to reject this purchase order.' using errcode = '42501';
  end if;

  v_admin_rejected := (v_appr = 'pending_final');   -- only the admin can reject at that step

  update purchase_orders
     set approval_status = 'rejected', rejected_by = auth.uid(), rejected_at = now(),
         rejection_reason = btrim(p_reason)
   where id = p_po;

  insert into po_approval_events (po_id, event, from_status, to_status, actor_id, note)
  values (p_po, 'rejected', v_appr, 'rejected', auth.uid(), btrim(p_reason));

  -- Back to procurement to fix and resubmit.
  perform public.fn_notify(v_sub, 'po_rejected',
    v_num || ' was sent back',
    'Reason: ' || btrim(p_reason) || ' — fix it and resubmit.', 'purchase_order', p_po);

  -- The admin overruled a PO the PM had already signed → keep the PM in the loop.
  if v_admin_rejected and v_pm is not null
     and v_pm <> coalesce(v_sub, '00000000-0000-0000-0000-000000000000') then
    perform public.fn_notify(v_pm, 'po_rejected',
      v_num || ' was rejected by the owner',
      'The purchase order you signed on your build was rejected. Reason: ' || btrim(p_reason),
      'purchase_order', p_po);
  end if;

  perform public.fn_audit('reject_po', 'purchase_order', p_po);
end $$;


-- Fix a rejected PO and send it round again. Procurement (or admin) only, and
-- only while it is rejected. If new lines are supplied they replace the old ones
-- and the totals are recomputed; vendor / delivery / terms are updated too. The
-- signatures are wiped and it re-enters the chain from the top — a project PO
-- goes back to its PM, a general PO straight to final approval — so a changed
-- price or vendor is re-verified, not waved through on the old signature.
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
    from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_appr <> 'rejected' then
    raise exception 'Only a rejected purchase order can be resubmitted.';
  end if;

  if v_project is not null then
    select pm_id into v_pm from projects where id = v_project;
  end if;
  v_next := case when v_pm is not null then 'pending_pm' else 'pending_final' end;

  -- Replace the lines + recompute totals when a new set is supplied.
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
       set vendor_id     = coalesce(p_vendor, vendor_id),
           delivery_date = coalesce(p_delivery_date, delivery_date),
           payment_terms = nullif(btrim(coalesce(p_payment_terms, '')), ''),
           notes         = nullif(btrim(coalesce(p_notes, '')), ''),
           ship_to       = nullif(btrim(coalesce(p_ship_to, '')), ''),
           subtotal = v_subtotal, tax_total = v_tax, amount = v_subtotal + v_tax
     where id = p_po;
  end if;

  -- Wipe the signatures and re-enter the chain from the top.
  update purchase_orders
     set approval_status = v_next, pm_id = v_pm,
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
-- 5. VIEW — the approvals queue, with how long each PO has been waiting
--    security_invoker so the reader's RLS on purchase_orders applies.
-- ════════════════════════════════════════════════════════════════════════════
drop view if exists public.v_po_pending_approvals;
create view public.v_po_pending_approvals with (security_invoker = on) as
  select
    po.id, po.po_number, po.approval_status, po.amount,
    po.project_id, po.pm_id, po.vendor_id, po.needed_by,
    v.name  as vendor_name,
    pr.code as project_code,
    po.submitted_at, po.submitted_by, po.pm_signed_at,
    case when po.approval_status = 'pending_pm'    then po.submitted_at
         when po.approval_status = 'pending_final' then po.pm_signed_at end as waiting_since,
    round(extract(epoch from (now() -
      case when po.approval_status = 'pending_pm'    then po.submitted_at
           when po.approval_status = 'pending_final' then po.pm_signed_at end)) / 3600.0, 1) as waiting_hours,
    (po.needed_by is not null and po.needed_by < current_date) as overdue
  from purchase_orders po
  left join vendors  v  on v.id  = po.vendor_id
  left join projects pr on pr.id = po.project_id
  where po.approval_status in ('pending_pm','pending_final')
  order by waiting_since asc nulls last;


-- ════════════════════════════════════════════════════════════════════════════
-- 6. RLS
-- ════════════════════════════════════════════════════════════════════════════

-- New tables aren't covered by the 0002 enable-RLS loop — turn it on here.
alter table public.company_settings   enable row level security;
alter table public.po_approval_events enable row level security;

-- Company settings: any staff can read (a PO shows the buyer block); admin edits.
drop policy if exists company_settings_read  on public.company_settings;
drop policy if exists company_settings_write on public.company_settings;
create policy company_settings_read  on public.company_settings for select using (public.is_staff());
create policy company_settings_write on public.company_settings for all
  using (public.is_admin()) with check (public.is_admin());

-- Approval events: readable by the roles that touch procurement; written only by
-- the SECURITY DEFINER functions above (no direct write policy).
drop policy if exists po_appr_events_read on public.po_approval_events;
create policy po_appr_events_read on public.po_approval_events for select
  using (public.has_role(array['admin','pm','procurement','store']));

-- Tighten purchase_orders: costs are now on the record, so keep them off the
-- shop floor (workshop / design / service / client). Read = the roles that need
-- it; writes still {admin,procurement}. Crucially, DROP the blanket insert path
-- — a PO must now be raised through fn_create_po so it enters the approval flow
-- instead of going live unsigned.
drop policy if exists purchase_orders_read   on public.purchase_orders;
drop policy if exists purchase_orders_write  on public.purchase_orders;
drop policy if exists purchase_orders_update on public.purchase_orders;
create policy purchase_orders_read on public.purchase_orders for select
  using (public.has_role(array['admin','pm','procurement','store']));
create policy purchase_orders_update on public.purchase_orders for update
  using (public.has_role(array['admin','procurement']))
  with check (public.has_role(array['admin','procurement']));

-- po_lines carry rates now — same read scope as the header.
drop policy if exists po_lines_read  on public.po_lines;
drop policy if exists po_lines_staff on public.po_lines;
create policy po_lines_read on public.po_lines for select
  using (public.has_role(array['admin','pm','procurement','store']));
-- po_lines_write ({admin,procurement}) from 0009 stays as-is.

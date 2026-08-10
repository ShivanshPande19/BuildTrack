-- 0017_stock_requests.sql
--
-- Store → Procurement essentials reorder loop.
--
-- Procurement doesn't only buy project materials (which the PM raises as
-- procurement_requirements, backward-scheduled against a delivery date). There
-- are general essentials — wheels, sheets, metal — that every trailer/kiosk
-- build consumes and that we keep in stock regardless of any one project.
--
-- Store watches inventory. When an essential runs low, Store raises a reorder
-- request straight to Procurement (mirroring how the PM raises project
-- requirements). Procurement sees it in "To Order" and cuts a general PO
-- (project_id null). On receipt fn_receive_po already tops up stock_items, and
-- now also closes the request.
--
-- This is manual on purpose: Store decides what and how much to reorder — no
-- automatic low-stock ordering, which tends to buy the wrong things.
--
-- Reuses the existing req_status enum ('pending','ordered','received').

create table if not exists public.stock_requests (
  id              uuid primary key default gen_random_uuid(),
  item_catalog_id uuid not null references item_catalog(id),
  qty             int  not null default 1 check (qty > 0),
  note            text,
  status          req_status not null default 'pending',
  requested_by    uuid references profiles(id),
  po_id           uuid references purchase_orders(id),
  created_at      timestamptz not null default now()
);

create index if not exists stock_requests_status_idx on public.stock_requests (status);
create index if not exists stock_requests_po_idx     on public.stock_requests (po_id);

alter table public.stock_requests enable row level security;

-- Read: any staff member (procurement acts on them, store/pm/admin see status).
create policy stock_requests_read on public.stock_requests
  for select using (public.has_role(array['admin','procurement','store','pm']));

-- Insert: store (or admin) raises the request. fn_request_stock is the intended
-- path, but this keeps a direct insert honest too.
create policy stock_requests_insert on public.stock_requests
  for insert with check (public.has_role(array['admin','store']));

-- Update: procurement (or admin) links a PO / advances status.
create policy stock_requests_update on public.stock_requests
  for update using (public.has_role(array['admin','procurement']))
  with check (public.has_role(array['admin','procurement']));


-- Store raises a reorder request and Procurement is notified — the same shape
-- as the PM → assignee notifications elsewhere in the app.
create or replace function public.fn_request_stock(
  p_item uuid, p_qty int, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text;
begin
  if not public.has_role(array['admin','store']) then
    raise exception 'Only store or admin can request stock.' using errcode = '42501';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity must be greater than zero.';
  end if;

  select name into v_name from item_catalog where id = p_item;
  if not found then raise exception 'Item not found.'; end if;

  insert into stock_requests (item_catalog_id, qty, note, requested_by)
  values (p_item, p_qty, nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_id;

  perform public.fn_notify_role(
    array['procurement','admin'], 'stock_request',
    'Stock reorder requested',
    format('%s x %s needed', p_qty, v_name),
    'stock_request', v_id, auth.uid());

  perform public.fn_audit('request_stock', 'stock_request', v_id);
  return v_id;
end $$;


-- Re-create fn_receive_po (from 0016) so that receiving a PO also closes any
-- stock reorder requests it was raised against — the same way it already closes
-- procurement_requirements. Body is otherwise identical to 0016.
create or replace function public.fn_receive_po(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status po_status; r record;
begin
  if not public.has_role(array['admin', 'procurement', 'store']) then
    raise exception 'Only procurement or store can receive a purchase order.' using errcode = '42501';
  end if;

  select status into v_status from purchase_orders where id = p_po;
  if not found then raise exception 'Purchase order not found.'; end if;
  if v_status = 'received' then
    raise exception 'This purchase order has already been received.';
  end if;
  if v_status not in ('dispatched', 'partial') then
    raise exception 'Mark the purchase order dispatched before receiving it.';
  end if;

  -- Mark the PO received and fully receive every line.
  update purchase_orders set status = 'received' where id = p_po;
  update po_lines set received_qty = qty where po_id = p_po;

  -- Add the received quantities to stock, one row per catalog item. A PO can
  -- list the same item on more than one line, so sum first. Update the existing
  -- stock row if there is one; otherwise open one, carrying the item's unit.
  for r in
    select item_catalog_id, sum(qty)::numeric as q
      from po_lines where po_id = p_po
     group by item_catalog_id
  loop
    update stock_items set quantity = quantity + r.q
     where item_catalog_id = r.item_catalog_id;
    if not found then
      insert into stock_items (item_catalog_id, quantity, unit)
      select r.item_catalog_id, r.q, coalesce(ic.unit, 'pcs')
        from item_catalog ic where ic.id = r.item_catalog_id;
    end if;
  end loop;

  -- Goods receipt note + close the requirements this PO was raised against.
  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;
  update stock_requests          set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

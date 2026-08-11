-- 0018_intake_serialized.sql
--
-- Intake, serialized-aware. Phase 2 of the inventory-truthfulness work.
--
-- Two kinds of item live in the catalog (item_catalog.serialized):
--   • Bulk / consumable (serialized = false) — screws, sheet, wire. On-hand is
--     a running quantity in stock_items.
--   • Serialized (serialized = true) — LED screens, inverters. Every physical
--     unit is a component_instance with its own serial; on-hand is how many are
--     'in_stock' (see StoreRepo.stock, Phase 1).
--
-- Until now fn_receive_po bumped stock_items for EVERY received line. For a
-- serialized item that double-counts: receive adds to stock_items AND Store
-- logs each unit as a component. So from here fn_receive_po only tops up
-- stock_items for bulk items; serialized items enter stock when Store logs
-- their serials (scanned off the vendor label at intake). The goods receipt and
-- requirement/stock-request closing behave exactly as before, for both kinds.
--
-- Body is otherwise identical to 0017's fn_receive_po (dispatch guard, GRN,
-- close procurement_requirements + stock_requests).

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

  -- Add received quantities to stock — BULK items only. Serialized items are
  -- counted from the component ledger, so topping up stock_items here would
  -- double-count them. A PO can list the same item on more than one line, so
  -- sum first; update the existing stock row or open one, carrying the unit.
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

  -- Goods receipt note + close the requirements this PO was raised against.
  insert into goods_receipts (po_id, status, received_by)
  values (p_po, 'complete', auth.uid());
  update procurement_requirements set status = 'received' where po_id = p_po;
  update stock_requests          set status = 'received' where po_id = p_po;

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

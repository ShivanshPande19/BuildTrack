-- 0013_stock_movement.sql — receiving a PO actually moves stock
--
-- Nothing ever wrote to stock_items after the seed, so the Store inventory and
-- its low-stock alerts were frozen: a received purchase order closed its
-- requirements and wrote a GRN, but the quantities never landed in stock.
--
-- The client-side markReceived() also could not fix this on its own —
-- stock_items is writable only by {admin,store} (0009), while receiving is done
-- by procurement — and it did four separate writes with no transaction. This
-- moves the whole operation into one security-definer RPC: atomic, permission
-- checked once, and able to touch stock_items.

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

  perform public.fn_audit('receive_po', 'purchase_order', p_po);
end $$;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Procurement — prepare a proper purchase order (pr4).
///
/// This is the single path a PO is raised through now: it captures the vendor,
/// the line items with **rate + GST**, and delivery / payment terms, so the
/// header totals are real and a proper PO document can be produced. On submit it
/// goes through `fn_create_po`, which enters it into the approval chain rather
/// than placing it live and unsigned.
///
/// Can be opened blank, or pre-filled from a To-Order alert (a project
/// requirement) or a Store reorder request — in which case it links that demand
/// so it leaves the To-Order list.
class NewPoScreen extends ConsumerStatefulWidget {
  const NewPoScreen({
    super.key,
    this.initialProjectId,
    this.initialItem,
    this.initialQty = 1,
    this.requirementId,
    this.stockRequest,
    this.generalOnly = false,
    this.editPo,
  });

  /// When set, the screen edits a rejected PO and resubmits it (fn_resubmit_po)
  /// instead of raising a new one.
  final PoDetail? editPo;

  /// Pre-fill: the project this PO is for (null = general / stock PO).
  final String? initialProjectId;
  /// Pre-fill: the item to order.
  final OptRef? initialItem;
  final int initialQty;
  /// Links a project requirement so it leaves To-Order when raised.
  final String? requirementId;
  /// Links a Store reorder request so it leaves To-Order when raised.
  final StockRequest? stockRequest;
  /// Force a general (no-project) PO — used for stock reorders.
  final bool generalOnly;

  @override
  ConsumerState<NewPoScreen> createState() => _NewPoScreenState();
}

class _Line {
  String? itemId;
  int qty = 1;
  final TextEditingController price = TextEditingController();
  double taxRate = 18; // GST %; most goods here sit at 18%
}

class _NewPoScreenState extends ConsumerState<NewPoScreen> {
  String? _projectId, _vendorId;
  DateTime? _delivery;
  final _termsC = TextEditingController();
  final List<_Line> _lines = [];
  final List<OptRef> _extraItems = []; // items created inline this session
  bool _saving = false;
  String? _error;

  static const _addNew = '__add_new__';
  static const _gstRates = <double>[0, 5, 12, 18, 28];
  static final _fmt = DateFormat('d MMM');
  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  bool get _isEdit => widget.editPo != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      // Re-open a rejected PO with everything it had, ready to fix.
      final po = widget.editPo!.po;
      _vendorId = po.vendorId;
      _delivery = po.deliveryDate;
      _termsC.text = po.paymentTerms ?? '';
      for (final it in widget.editPo!.items) {
        final line = _Line()
          ..itemId = it.itemCatalogId
          ..qty = it.qty < 1 ? 1 : it.qty
          ..taxRate = _gstRates.contains(it.taxRate) ? it.taxRate : 18;
        if (it.unitPrice > 0) {
          line.price.text = it.unitPrice % 1 == 0
              ? it.unitPrice.toInt().toString()
              : it.unitPrice.toString();
        }
        if (it.itemCatalogId != null) _extraItems.add(OptRef(it.itemCatalogId!, it.name));
        _lines.add(line);
      }
      if (_lines.isEmpty) _lines.add(_Line());
      return;
    }
    _projectId = widget.generalOnly ? null : widget.initialProjectId;
    final l = _Line();
    if (widget.initialItem != null) {
      l.itemId = widget.initialItem!.id;
      _extraItems.add(widget.initialItem!);
    }
    l.qty = widget.initialQty < 1 ? 1 : widget.initialQty;
    _lines.add(l);
  }

  @override
  void dispose() {
    _termsC.dispose();
    for (final l in _lines) { l.price.dispose(); }
    super.dispose();
  }

  double _priceOf(_Line l) => double.tryParse(l.price.text.trim()) ?? 0;
  double get _subtotal => _lines.fold(0, (s, l) => s + l.qty * _priceOf(l));
  double get _tax => _lines.fold(0, (s, l) => s + l.qty * _priceOf(l) * l.taxRate / 100.0);
  double get _grand => _subtotal + _tax;

  Future<void> _submit() async {
    final valid = _lines.where((l) => l.itemId != null).toList();
    if (!_isEdit && _vendorId == null) {
      setState(() => _error = 'Pick a vendor.');
      return;
    }
    if (valid.isEmpty) {
      setState(() => _error = 'Add at least one item.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final lines = [
      for (final l in valid)
        (itemId: l.itemId!, qty: l.qty, unitPrice: _priceOf(l), taxRate: l.taxRate),
    ];
    final terms = _termsC.text.trim().isEmpty ? null : _termsC.text.trim();
    try {
      final repo = ref.read(procurementRepoProvider);
      if (_isEdit) {
        await repo.resubmitPo(widget.editPo!.po.id,
          vendorId: _vendorId, deliveryDate: _delivery, paymentTerms: terms, lines: lines);
        ref.invalidate(poDetailProvider(widget.editPo!.po.id));
      } else {
        await repo.createPo(
          projectId: _projectId, vendorId: _vendorId, deliveryDate: _delivery, paymentTerms: terms,
          requirementId: widget.requirementId, stockRequestId: widget.stockRequest?.id, lines: lines);
      }
      // Refresh everything the PO touches.
      ref.invalidate(purchaseOrdersProvider);
      ref.invalidate(poApprovalsProvider);
      ref.invalidate(toOrderProvider);
      ref.invalidate(stockRequestsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text(_isEdit
            ? 'Resubmitted — sent for approval.'
            : 'Purchase order raised — sent for approval.')));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Quick inline "create catalog item" sheet — returns the new item (or null).
  Future<OptRef?> _addItemSheet() {
    final nameC = TextEditingController();
    final catC = TextEditingController();
    final leadC = TextEditingController();
    bool busy = false;
    String? err;
    return showModalBottomSheet<OptRef>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Widget field(String label, TextEditingController c, {String? hint, bool number = false}) => Container(
          margin: const EdgeInsets.only(bottom: 11),
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
            TextField(controller: c, keyboardType: number ? TextInputType.number : null,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
              decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.only(top: 4),
                hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500))),
          ]),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: BT.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
              Text('New item', style: display(20, w: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Adds it to the catalog and selects it here.',
                style: TextStyle(color: BT.mut, fontSize: 12.5)),
              const SizedBox(height: 16),
              field('ITEM NAME', nameC, hint: 'Espresso machine'),
              field('CATEGORY', catC, hint: 'Equipment / Electrical …'),
              field('LEAD TIME (DAYS)', leadC, hint: '7', number: true),
              if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text(err!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
              const SizedBox(height: 4),
              busy
                ? const Center(child: CircularProgressIndicator(color: BT.ink))
                : PrimaryButton('Add item', icon: Icons.check, onTap: () async {
                    if (nameC.text.trim().isEmpty) { setSheet(() => err = 'Item name is required.'); return; }
                    setSheet(() { busy = true; err = null; });
                    try {
                      final created = await ref.read(procurementRepoProvider).createItem(
                        name: nameC.text.trim(),
                        category: catC.text.trim().isEmpty ? null : catC.text.trim(),
                        leadTimeDays: int.tryParse(leadC.text.trim()) ?? 0);
                      if (ctx.mounted) Navigator.pop(ctx, created);
                    } catch (e) {
                      setSheet(() { busy = false; err = '$e'; });
                    }
                  }),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(allProjectsProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final providerItems = ref.watch(itemsProvider).valueOrNull ?? [];
    final items = {for (final o in [...providerItems, ..._extraItems]) o.id: o}.values.toList();
    final locked = widget.generalOnly; // general/stock PO can't take a project
    // A DropdownButton must not carry a non-null value that isn't in its items
    // (asserts). While projects are still loading, fall back to null.
    final projValue = projects.any((p) => p.id == _projectId) ? _projectId : null;

    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
          ]),
          const SizedBox(height: 14),
          Text(_isEdit ? 'Edit PO' : 'New PO', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(_isEdit
            ? 'Fix what was flagged and send it round again.'
            : 'Goes to the PM to sign, then for final approval.',
            style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 16),

          // Why it came back — so procurement fixes the right thing.
          if (_isEdit && (widget.editPo!.po.rejectionReason?.isNotEmpty ?? false)) ...[
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(13)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.undo_rounded, size: 18, color: BT.coral),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Sent back', style: TextStyle(fontWeight: FontWeight.w700, color: BT.coral, fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Text(widget.editPo!.po.rejectionReason!, style: const TextStyle(fontSize: 12.5, height: 1.3)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          _label('PROJECT'),
          if (_isEdit)
            _staticField(widget.editPo!.po.projectCode ?? 'General stock')
          else if (locked)
            _staticField('General stock — no project')
          else
            _dropdown<String?>(
              value: projValue, hint: 'General (no project)',
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('General (no project)')),
                for (final p in projects)
                  DropdownMenuItem<String?>(value: p.id, child: Text('${p.code} · ${p.name}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
          if (!_isEdit) ...[
            const SizedBox(height: 6),
            Text(_projectId == null
              ? 'A general PO skips the PM and goes straight to final approval.'
              : 'A project PO is signed by the build\'s PM first.',
              style: const TextStyle(color: BT.mut2, fontSize: 11.5)),
          ],

          const SizedBox(height: 12),
          _label('VENDOR'),
          _dropdown<String>(
            value: _vendorId, hint: 'Select vendor',
            items: [for (final v in vendors) DropdownMenuItem(value: v.id, child: Text(v.name))],
            onChanged: (v) => setState(() => _vendorId = v),
          ),

          const SectionLabel('Items'),
          ...List.generate(_lines.length, (i) => _lineCard(i, items)),
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _lines.add(_Line())),
            child: Container(
              height: 46, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 18, color: BT.ink), SizedBox(width: 6),
                Text('Add item', style: TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),

          const SizedBox(height: 16),
          _label('EXPECTED DELIVERY'),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context,
                initialDate: _delivery ?? now.add(const Duration(days: 7)),
                firstDate: now, lastDate: now.add(const Duration(days: 365)));
              if (d != null) setState(() => _delivery = d);
            },
            child: _staticField(_delivery == null ? 'Pick date' : _fmt.format(_delivery!),
              placeholder: _delivery == null),
          ),
          const SizedBox(height: 12),
          _label('PAYMENT TERMS'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
            child: TextField(controller: _termsC,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BT.ink),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
                hintText: 'e.g. 50% advance, balance on delivery',
                hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w500))),
          ),

          const SizedBox(height: 18),
          _totals(),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton(_isEdit ? 'Resubmit for approval' : 'Raise & send for approval',
                icon: Icons.send_rounded, onTap: _submit),
        ],
      )),
    );
  }

  Widget _totals() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      _totalRow('Subtotal', _money.format(_subtotal), muted: true),
      const SizedBox(height: 6),
      _totalRow('GST', _money.format(_tax), muted: true),
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: BT.line)),
      _totalRow('Total', _money.format(_grand)),
    ]),
  );

  Widget _totalRow(String label, String value, {bool muted = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(fontSize: muted ? 13 : 15,
      fontWeight: muted ? FontWeight.w500 : FontWeight.w700, color: muted ? BT.mut : BT.ink)),
    Text(value, style: muted
      ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BT.mut)
      : display(18, w: FontWeight.w700)),
  ]);

  Widget _lineCard(int i, List<OptRef> items) {
    final l = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
        child: Column(children: [
          Row(children: [
            Expanded(child: _dropdown<String>(
              value: l.itemId, hint: 'Select item', dense: true,
              items: [
                for (final o in items) DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis)),
                const DropdownMenuItem(value: _addNew, child: Row(children: [
                  Icon(Icons.add_rounded, size: 17, color: BT.ink), SizedBox(width: 6),
                  Text('Add new item', style: TextStyle(fontWeight: FontWeight.w700)),
                ])),
              ],
              onChanged: (v) async {
                if (v == _addNew) {
                  final created = await _addItemSheet();
                  if (created != null) setState(() { _extraItems.add(created); l.itemId = created.id; });
                  ref.invalidate(itemsProvider);
                } else {
                  setState(() => l.itemId = v);
                }
              },
            )),
            if (_lines.length > 1) GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _lines.removeAt(i)),
              child: const Padding(padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close_rounded, size: 20, color: BT.mut2)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // qty stepper
            Container(
              height: 46,
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _qtyBtn(Icons.remove, () { if (l.qty > 1) setState(() => l.qty--); }),
                SizedBox(width: 26, child: Text('${l.qty}', textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
                _qtyBtn(Icons.add, () => setState(() => l.qty++)),
              ]),
            ),
            const SizedBox(width: 8),
            // unit price
            Expanded(child: Container(
              height: 46, padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Text('₹', style: TextStyle(color: BT.mut, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Expanded(child: TextField(
                  controller: l.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BT.ink),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true,
                    hintText: 'Rate', hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
                )),
              ]),
            )),
            const SizedBox(width: 8),
            // GST %
            Container(
              height: 46, padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
              child: DropdownButtonHideUnderline(child: DropdownButton<double>(
                value: l.taxRate, isDense: true,
                icon: const Icon(Icons.expand_more_rounded, size: 18, color: BT.mut2),
                style: const TextStyle(color: BT.ink, fontSize: 13.5, fontWeight: FontWeight.w700),
                items: [for (final r in _gstRates)
                  DropdownMenuItem(value: r, child: Text('${r.toInt()}%'))],
                onChanged: (v) => setState(() => l.taxRate = v ?? 18),
              )),
            ),
          ]),
          if (_priceOf(l) > 0) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerRight, child: Text(
              '${_money.format(l.qty * _priceOf(l))} + ${l.taxRate.toInt()}% GST',
              style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600))),
          ),
        ]),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: SizedBox(width: 32, height: 46, child: Icon(icon, size: 18, color: BT.ink)));

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(t, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)));

  Widget _dropdown<T>({required T? value, required String hint,
      required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged, bool dense = false}) => Container(
    height: dense ? 46 : 52, padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(color: dense ? BT.card2 : BT.card, borderRadius: BorderRadius.circular(dense ? 12 : 14),
      border: dense ? null : Border.all(color: BT.line)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value, isExpanded: true, hint: Text(hint, style: const TextStyle(color: BT.mut2, fontSize: 14)),
      icon: const Icon(Icons.expand_more_rounded, color: BT.mut2),
      style: const TextStyle(color: BT.ink, fontSize: 14, fontWeight: FontWeight.w600),
      items: items, onChanged: onChanged,
    )),
  );

  Widget _staticField(String text, {bool placeholder = false}) => Container(
    height: 52, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
      color: placeholder ? BT.mut2 : BT.ink)),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Procurement — create a purchase order manually (pr4).
class NewPoScreen extends ConsumerStatefulWidget {
  const NewPoScreen({super.key});
  @override
  ConsumerState<NewPoScreen> createState() => _NewPoScreenState();
}

class _Line {
  String? itemId;
  int qty = 1;
}

class _NewPoScreenState extends ConsumerState<NewPoScreen> {
  String? _projectId, _vendorId;
  final DateTime _orderDate = DateTime.now();
  DateTime? _expected;
  final List<_Line> _lines = [_Line()];
  final List<OptRef> _extraItems = []; // items created inline this session
  bool _saving = false;
  String? _error;

  static const _addNew = '__add_new__';
  static final _fmt = DateFormat('d MMM');

  Future<void> _submit() async {
    final valid = _lines.where((l) => l.itemId != null).toList();
    if (_projectId == null || _vendorId == null) {
      setState(() => _error = 'Pick a project and a vendor.');
      return;
    }
    if (valid.isEmpty) {
      setState(() => _error = 'Add at least one item.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(procurementRepoProvider).createManualPo(
        projectId: _projectId!, vendorId: _vendorId!,
        orderDate: _orderDate, expectedDate: _expected,
        lines: [for (final l in valid) (itemId: l.itemId!, qty: l.qty)],
      );
      ref.invalidate(purchaseOrdersProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Purchase order created.')));
      }
    } catch (e) {
      setState(() => _error = '$e');
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
    // Merge catalog + inline-created items, de-duplicated by id.
    final items = {for (final o in [...providerItems, ..._extraItems]) o.id: o}.values.toList();

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
          Text('New PO', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 18),

          _label('PROJECT'),
          _dropdown<String>(
            value: _projectId, hint: 'Select project',
            items: [for (final p in projects) DropdownMenuItem(value: p.id, child: Text('${p.code} · ${p.name}'))],
            onChanged: (v) => setState(() => _projectId = v),
          ),
          const SizedBox(height: 12),
          _label('VENDOR'),
          _dropdown<String>(
            value: _vendorId, hint: 'Select vendor',
            items: [for (final v in vendors) DropdownMenuItem(value: v.id, child: Text(v.name))],
            onChanged: (v) => setState(() => _vendorId = v),
          ),

          const SectionLabel('Items'),
          ...List.generate(_lines.length, (i) => _lineRow(i, items)),
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
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('ORDER DATE'),
              _staticField(_fmt.format(_orderDate)),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('EXPECTED BY'),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final d = await showDatePicker(context: context,
                    initialDate: _expected ?? _orderDate.add(const Duration(days: 7)),
                    firstDate: _orderDate, lastDate: _orderDate.add(const Duration(days: 365)));
                  if (d != null) setState(() => _expected = d);
                },
                child: _staticField(_expected == null ? 'Pick date' : _fmt.format(_expected!),
                  placeholder: _expected == null),
              ),
            ])),
          ]),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

          const SizedBox(height: 22),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Create & send', icon: Icons.send_rounded, onTap: _submit),
        ],
      )),
    );
  }

  Widget _lineRow(int i, List<OptRef> items) {
    final l = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(child: _dropdown<String>(
          value: l.itemId, hint: 'Select item',
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
        const SizedBox(width: 10),
        // qty stepper
        Container(
          height: 52,
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _qtyBtn(Icons.remove, () { if (l.qty > 1) setState(() => l.qty--); }),
            SizedBox(width: 24, child: Text('${l.qty}', textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700))),
            _qtyBtn(Icons.add, () => setState(() => l.qty++)),
          ]),
        ),
        if (_lines.length > 1) GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _lines.removeAt(i)),
          child: const Padding(padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.close_rounded, size: 20, color: BT.mut2)),
        ),
      ]),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: SizedBox(width: 34, height: 52, child: Icon(icon, size: 18, color: BT.ink)));

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(t, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)));

  Widget _dropdown<T>({required T? value, required String hint,
      required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => Container(
    height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
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

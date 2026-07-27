import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Build a custom workflow template: ordered stages (name + duration) and,
/// per stage, its BOM (items needed). BOM → auto-generated requirements on onboarding.
class CreateTemplate extends ConsumerStatefulWidget {
  const CreateTemplate({super.key});
  @override
  ConsumerState<CreateTemplate> createState() => _CreateTemplateState();
}

class _StageRow {
  final TextEditingController name;
  final TextEditingController days;
  final List<StageItemDraft> items;
  _StageRow(String n, int d)
      : name = TextEditingController(text: n),
        days = TextEditingController(text: '$d'),
        items = [];
}

class _CreateTemplateState extends ConsumerState<CreateTemplate> {
  final _name = TextEditingController();
  final List<_StageRow> _rows = [];
  final List<OptRef> _extraItems = []; // items created inline
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final s in const [
      ['Design & Layout', 4], ['Chassis & Structure', 7], ['Exterior cladding', 3],
      ['Electrical work', 4], ['Interior & Equipment', 3], ['Paint & Branding', 2], ['Testing & Delivery', 2],
    ]) {
      _rows.add(_StageRow(s[0] as String, s[1] as int));
    }
  }

  Future<void> _save() async {
    final stages = <StageDraft>[];
    for (final r in _rows) {
      final n = r.name.text.trim();
      if (n.isEmpty) continue;
      stages.add(StageDraft(n, int.tryParse(r.days.text.trim()) ?? 1, items: r.items));
    }
    if (_name.text.trim().isEmpty || stages.isEmpty) {
      setState(() => _error = 'Template name and at least one stage are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final created = await ref.read(adminRepoProvider).createTemplate(_name.text.trim(), null, stages);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() { _error = 'Failed: $e'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
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
          const SizedBox(height: 12),
          Text('New template', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Stages, durations, and the parts each stage needs (auto-ordered later).',
            style: TextStyle(color: BT.mut, fontSize: 13, height: 1.35)),
          const SizedBox(height: 18),
          _text('Template name', _name, hint: 'Momo Cart'),
          const SectionLabel('Stages (in order)'),
          ...List.generate(_rows.length, (i) => _stageCard(i)),
          GestureDetector(onTap: () => setState(() => _rows.add(_StageRow('', 2))), child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line), color: BT.card),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 18, color: BT.ink), SizedBox(width: 6),
              Text('Add stage', style: TextStyle(fontWeight: FontWeight.w600)),
            ]))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Save template', icon: Icons.check, onTap: _save),
        ],
      )),
    );
  }

  Widget _stageCard(int i) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 26, height: 26, alignment: Alignment.center,
              decoration: const BoxDecoration(color: BT.card2, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BT.mut))),
            const SizedBox(width: 10),
            Expanded(child: _boxField(r.name, 'Stage name')),
            const SizedBox(width: 8),
            SizedBox(width: 58, child: _boxField(r.days, 'days', number: true)),
            IconButton(onPressed: () => setState(() => _rows.removeAt(i)),
              icon: const Icon(Icons.close, size: 18, color: BT.mut2), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: [
            ...r.items.asMap().entries.map((e) => _itemChip(i, e.key, e.value)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _addItem(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 15, color: BT.ink), SizedBox(width: 4),
                  Text('item', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BT.ink)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _itemChip(int stageIndex, int itemIndex, StageItemDraft it) => Container(
    padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
    decoration: BoxDecoration(color: BT.lav, borderRadius: BorderRadius.circular(999)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${it.label} ×${it.qty}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BT.ink)),
      const SizedBox(width: 5),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _rows[stageIndex].items.removeAt(itemIndex)),
        child: const Icon(Icons.close_rounded, size: 15, color: Color(0xFF3A2A4A))),
    ]),
  );

  Future<void> _addItem(int stageIndex) async {
    String? itemId;
    String? itemLabel;
    int qty = 1;
    final catalog = {
      for (final o in [...(ref.read(itemsProvider).valueOrNull ?? <OptRef>[]), ..._extraItems]) o.id: o
    }.values.toList();

    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
            Text('Add item to stage', style: display(19, w: FontWeight.w600)),
            const SizedBox(height: 14),
            Container(
              height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: itemId, isExpanded: true,
                hint: const Text('Select item', style: TextStyle(color: BT.mut2, fontSize: 14)),
                icon: const Icon(Icons.expand_more_rounded, color: BT.mut2),
                style: const TextStyle(color: BT.ink, fontSize: 14, fontWeight: FontWeight.w600),
                items: [
                  for (final o in catalog) DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem(value: '__add__', child: Row(children: [
                    Icon(Icons.add_rounded, size: 17, color: BT.ink), SizedBox(width: 6),
                    Text('Add new item', style: TextStyle(fontWeight: FontWeight.w700)),
                  ])),
                ],
                onChanged: (v) async {
                  if (v == '__add__') {
                    final created = await _promptNewItem();
                    if (created != null) {
                      _extraItems.add(created); catalog.add(created);
                      setS(() { itemId = created.id; itemLabel = created.label; });
                    }
                  } else {
                    setS(() { itemId = v; itemLabel = catalog.firstWhere((o) => o.id == v).label; });
                  }
                },
              )),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Qty', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                height: 46,
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () { if (qty > 1) setS(() => qty--); },
                    child: const SizedBox(width: 40, height: 46, child: Icon(Icons.remove, size: 18))),
                  SizedBox(width: 30, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setS(() => qty++),
                    child: const SizedBox(width: 40, height: 46, child: Icon(Icons.add, size: 18))),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            PrimaryButton('Add', icon: Icons.check, onTap: () {
              if (itemId == null) return;
              setState(() => _rows[stageIndex].items.add(StageItemDraft(itemId!, itemLabel ?? 'Item', qty)));
              Navigator.pop(ctx);
            }),
          ]),
        ),
      )),
    );
  }

  Future<OptRef?> _promptNewItem() {
    final nameC = TextEditingController();
    final leadC = TextEditingController();
    String? e;
    return showDialog<OptRef>(context: context, builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('New item', style: display(18, w: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(nameC, 'Item name'),
        const SizedBox(height: 10),
        _dialogField(leadC, 'Lead time (days)', number: true),
        if (e != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(e!, style: const TextStyle(color: BT.coral, fontSize: 12))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () async {
          if (nameC.text.trim().isEmpty) { setD(() => e = 'Name required'); return; }
          final created = await ref.read(procurementRepoProvider).createItem(
            name: nameC.text.trim(), leadTimeDays: int.tryParse(leadC.text.trim()) ?? 0);
          ref.invalidate(itemsProvider);
          if (dctx.mounted) Navigator.pop(dctx, created);
        }, child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    )));
  }

  Widget _dialogField(TextEditingController c, String hint, {bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: TextField(controller: c, keyboardType: number ? TextInputType.number : null,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(hintText: hint, border: InputBorder.none)),
  );

  Widget _text(String label, TextEditingController c, {String? hint}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextField(controller: c, decoration: InputDecoration(labelText: label, hintText: hint,
      border: InputBorder.none, labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
  );

  Widget _boxField(TextEditingController c, String hint, {bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: TextField(controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(hintText: hint, border: InputBorder.none, isDense: true,
        hintStyle: const TextStyle(color: BT.mut2, fontSize: 13))),
  );
}

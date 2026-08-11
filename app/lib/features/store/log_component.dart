import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/barcode_scanner.dart';
import '../../shared/photo_picker.dart';
import '../../shared/widgets.dart';

/// Store — log a component at intake (st3): item + serial + warranty + assign to build.
/// Feeds traceability + recall (Hero #2).
class LogComponent extends ConsumerStatefulWidget {
  const LogComponent({super.key});
  @override
  ConsumerState<LogComponent> createState() => _LogComponentState();
}

class _LogComponentState extends ConsumerState<LogComponent> {
  final _serial = TextEditingController();
  String? _itemId, _vendorId, _projectId;
  DateTime? _warrantyEnd;
  PickedPhoto? _bill; // bill/invoice image, uploaded on save
  final List<OptRef> _extraItems = [];
  bool _saving = false;
  String? _error;

  static final _fmt = DateFormat('d MMM yyyy');

  // Scan the vendor's barcode/QR straight into the serial field. Most
  // serialized parts (LED screens, inverters) ship with a unique serial label,
  // so this is the fast, typo-free path at intake.
  Future<void> _scanSerial() async {
    final code = await Navigator.push<String>(context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(title: 'Scan serial')));
    if (code != null && code.trim().isNotEmpty) {
      setState(() => _serial.text = code.trim());
    }
  }

  Future<void> _save({bool another = false}) async {
    if (_itemId == null || _serial.text.trim().isEmpty) {
      setState(() => _error = 'Item and serial number are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(storeRepoProvider);
      // Upload the bill first (if one was attached) so its URL goes in with the
      // component in a single insert.
      String? billUrl;
      if (_bill != null) {
        billUrl = await repo.uploadBill(_bill!.bytes,
          filename: _bill!.filename, contentType: _bill!.contentType);
      }
      final saved = _serial.text.trim();
      await repo.logComponent(
        itemId: _itemId!, serial: saved,
        vendorId: _vendorId, warrantyEnd: _warrantyEnd, projectId: _projectId, billUrl: billUrl);
      ref.invalidate(componentsProvider);
      if (!mounted) return;
      if (another) {
        // Receiving several units of the same item: keep item/vendor/warranty/
        // bill, clear just the serial, and stay on the screen for the next scan.
        setState(() => _serial.clear());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text('$saved logged · scan the next unit')));
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text('$saved logged to inventory')));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerItems = ref.watch(itemsProvider).valueOrNull ?? <OptRef>[];
    final items = {for (final o in [...providerItems, ..._extraItems]) o.id: o}.values.toList();
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final projects = ref.watch(allProjectsProvider).valueOrNull ?? [];

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
          const SizedBox(height: 12),
          Text('Log component', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Records serial, warranty & build — the basis for recall.',
            style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 18),

          _label('ITEM'),
          _dropdown<String>(value: _itemId, hint: 'Select item', items: [
            for (final o in items) DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(value: '__add__', child: Row(children: [
              Icon(Icons.add_rounded, size: 17, color: BT.ink), SizedBox(width: 6),
              Text('Add new item', style: TextStyle(fontWeight: FontWeight.w700)),
            ])),
          ], onChanged: (v) async {
            if (v == '__add__') {
              final created = await _promptNewItem();
              if (created != null) setState(() { _extraItems.add(created); _itemId = created.id; });
              ref.invalidate(itemsProvider);
            } else { setState(() => _itemId = v); }
          }),
          const SizedBox(height: 11),

          _label('SERIAL NUMBER'),
          Row(children: [
            Expanded(child: _textField(_serial, 'SN-88213')),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _scanSerial,
              child: Container(width: 52, height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.qr_code_scanner_rounded, size: 22, color: BT.lime)),
            ),
          ]),
          const SizedBox(height: 11),

          _label('VENDOR (optional)'),
          _dropdown<String>(value: _vendorId, hint: 'Select vendor',
            items: [for (final v in vendors) DropdownMenuItem(value: v.id, child: Text(v.name))],
            onChanged: (v) => setState(() => _vendorId = v)),
          const SizedBox(height: 11),

          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('ASSIGN TO BUILD (optional)'),
              _dropdown<String>(value: _projectId, hint: 'In store',
                items: [for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.code, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _projectId = v)),
            ])),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('WARRANTY TILL'),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final d = await showDatePicker(context: context,
                    initialDate: _warrantyEnd ?? DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) setState(() => _warrantyEnd = d);
                },
                child: Container(height: 52, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
                  child: Text(_warrantyEnd == null ? 'Pick date' : _fmt.format(_warrantyEnd!),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _warrantyEnd == null ? BT.mut2 : BT.ink))),
              ),
            ])),
          ]),

          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final picked = await pickPhoto(context);
              if (picked != null) setState(() => _bill = picked);
            },
            child: Container(height: 50, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _bill == null ? BT.card : BT.lime,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _bill == null ? BT.line : Colors.transparent)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_bill == null ? Icons.attach_file_rounded : Icons.check_rounded, size: 18, color: BT.ink),
                const SizedBox(width: 8),
                Text(_bill == null ? 'Attach bill / invoice' : 'Bill attached · ${_bill!.sizeLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                if (_bill != null) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _bill = null),
                    child: const Icon(Icons.close_rounded, size: 17, color: Color(0xFF3A4A12))),
                ],
              ])),
          ),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : Column(children: [
                PrimaryButton('Save to inventory', icon: Icons.check, onTap: () => _save()),
                const SizedBox(height: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _save(another: true),
                  child: Container(height: 50, alignment: Alignment.center,
                    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_rounded, size: 18, color: BT.ink),
                      SizedBox(width: 8),
                      Text('Save & log another', style: TextStyle(fontWeight: FontWeight.w600, color: BT.ink)),
                    ])),
                ),
              ]),
        ],
      )),
    );
  }

  Future<OptRef?> _promptNewItem() {
    final nameC = TextEditingController();
    String? e;
    return showDialog<OptRef>(context: context, builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('New item', style: display(18, w: FontWeight.w600)),
      // The validation message ('Name required') was assigned to `e` but never
      // shown, so an empty name looked like the Add button simply did nothing.
      // Rendering it fixes both the dead variable and the silent failure.
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(controller: nameC, decoration: const InputDecoration(hintText: 'Item name', border: InputBorder.none)),
        ),
        if (e != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(e!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () async {
          if (nameC.text.trim().isEmpty) { setD(() => e = 'Name required'); return; }
          final created = await ref.read(procurementRepoProvider).createItem(name: nameC.text.trim());
          if (dctx.mounted) Navigator.pop(dctx, created);
        }, child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    )));
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(t, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)));

  Widget _textField(TextEditingController c, String hint) => Container(
    height: 52, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: TextField(controller: c,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
      decoration: InputDecoration(isDense: true, border: InputBorder.none,
        hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500))),
  );

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
}

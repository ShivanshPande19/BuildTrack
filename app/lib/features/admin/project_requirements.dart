import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Materials & order-by (Hero #1) — a project's procurement requirements,
/// fully editable: add / change qty / change needed-by / remove.
/// order_by is auto-computed by the backend (needed_by − lead − buffer).
class ProjectRequirementsScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? projectCode;
  /// Admin opens this read-only (monitor). Owning roles (PM/Procurement) open it editable.
  final bool editable;
  const ProjectRequirementsScreen({super.key, required this.projectId, this.projectCode, this.editable = false});
  @override
  ConsumerState<ProjectRequirementsScreen> createState() => _ProjectRequirementsScreenState();
}

class _ProjectRequirementsScreenState extends ConsumerState<ProjectRequirementsScreen> {
  static final _fmt = DateFormat('d MMM');
  final List<OptRef> _extraItems = []; // items created inline this session

  int? _daysLeft(DateTime? orderBy) => orderBy == null
      ? null
      : DateUtils.dateOnly(orderBy).difference(DateUtils.dateOnly(DateTime.now())).inDays;

  ({String label, Color color}) _pill(DateTime? orderBy) {
    final d = _daysLeft(orderBy);
    if (d == null) return (label: 'No date', color: BT.mut2);
    if (d <= 0) return (label: 'Order today', color: BT.coral);
    if (d <= 3) return (label: '${d}d left', color: BT.amber);
    return (label: 'On time', color: BT.lime);
  }

  void _refresh() {
    ref.invalidate(requirementsProvider(widget.projectId));
    ref.invalidate(toOrderProvider);   // Procurement To-Order
    ref.invalidate(fleetProvider);     // Admin needs-attention
  }

  @override
  Widget build(BuildContext context) {
    final reqs = ref.watch(requirementsProvider(widget.projectId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(requirementsProvider(widget.projectId).future),
        child: ListView(
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
            if (widget.projectCode != null)
              Text(widget.projectCode!, style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text('Materials & order-by', style: display(27, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(widget.editable
              ? 'Order-by date auto-updates from needed-by − lead time − buffer.'
              : 'Read-only overview. Order-by = needed-by − lead time − buffer.',
              style: const TextStyle(color: BT.mut, fontSize: 12.5, height: 1.35)),
            const SizedBox(height: 16),
            reqs.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load materials.\n$e',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) => list.isEmpty
                ? EmptyState(icon: Icons.inventory_2_outlined, tint: BT.lav,
                    title: 'No materials yet',
                    subtitle: widget.editable
                      ? 'Add the parts this build needs — each gets an order-by alert.'
                      : 'Materials will appear here once the build plan is set.')
                : Column(children: list.map(_row).toList()),
            ),
          ],
        ),
      )),
      floatingActionButton: widget.editable
        ? FloatingActionButton.extended(
            backgroundColor: BT.lime, foregroundColor: BT.ink,
            onPressed: () => _openSheet(null),
            icon: const Icon(Icons.add), label: const Text('Add material'))
        : null,
    );
  }

  Widget _row(Requirement r) {
    final p = _pill(r.orderBy);
    final ordered = r.status != 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (widget.editable && !ordered) ? () => _openSheet(r) : null,
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 3),
              Text('qty ${r.qty}'
                '${r.neededBy != null ? ' · needed ${_fmt.format(r.neededBy!)}' : ''}'
                '${r.orderBy != null ? ' · order by ${_fmt.format(r.orderBy!)}' : ''}',
                style: const TextStyle(color: BT.mut, fontSize: 12)),
            ])),
            const SizedBox(width: 8),
            StatusPill(ordered ? 'Ordered' : p.label, color: ordered ? BT.sky : p.color),
          ]),
        ),
      ),
    );
  }

  // ── add / edit sheet ────────────────────────────────────────────
  Future<void> _openSheet(Requirement? existing) async {
    final isEdit = existing != null;
    String? itemId = existing?.itemCatalogId;
    String? itemName = existing?.itemName;
    int qty = existing?.qty ?? 1;
    DateTime? neededBy = existing?.neededBy;
    bool busy = false;
    String? err;

    // catalog items available for picking (add mode)
    // The empty fallback needs its element type spelled out: `?? []` infers
    // List<dynamic>, which makes `catalog` dynamic and `o.id` / `o.label` below
    // untyped (strict-casts then rejects them). `<OptRef>[]` keeps it OptRef.
    final catalog = {
      for (final o in [...(ref.read(itemsProvider).valueOrNull ?? <OptRef>[]), ..._extraItems]) o.id: o
    }.values.toList();

    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
              Text(isEdit ? 'Edit material' : 'Add material', style: display(20, w: FontWeight.w600)),
              const SizedBox(height: 16),

              // ITEM
              const Text('ITEM', style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (isEdit)
                _readonlyField(itemName ?? 'Item')
              else
                _sheetDropdown(
                  value: itemId,
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
                        _extraItems.add(created);
                        catalog.add(created);
                        setS(() { itemId = created.id; itemName = created.label; });
                        ref.invalidate(itemsProvider);
                      }
                    } else {
                      setS(() => itemId = v);
                    }
                  },
                ),
              const SizedBox(height: 14),

              // QTY + NEEDED BY
              Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('QTY', style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    height: 52,
                    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _qtyBtn(Icons.remove, () { if (qty > 1) setS(() => qty--); }),
                      SizedBox(width: 30, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                      _qtyBtn(Icons.add, () => setS(() => qty++)),
                    ]),
                  ),
                ]),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('NEEDED BY', style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final d = await showDatePicker(context: ctx,
                        initialDate: neededBy ?? DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 730)));
                      if (d != null) setS(() => neededBy = d);
                    },
                    child: Container(
                      height: 52, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
                      child: Text(neededBy == null ? 'Pick date' : _fmt.format(neededBy!),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: neededBy == null ? BT.mut2 : BT.ink)),
                    ),
                  ),
                ])),
              ]),

              if (err != null) Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(err!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

              const SizedBox(height: 18),
              busy
                ? const Center(child: CircularProgressIndicator(color: BT.ink))
                : Row(children: [
                    if (isEdit) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await ref.read(projectsRepoProvider).deleteRequirement(existing.id);
                          _refresh();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Container(width: 54, height: 54, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.delete_outline_rounded, color: BT.coral)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: PrimaryButton(isEdit ? 'Save' : 'Add material', icon: Icons.check,
                      onTap: () async {
                        if (!isEdit && itemId == null) { setS(() => err = 'Pick an item.'); return; }
                        setS(() { busy = true; err = null; });
                        try {
                          final repo = ref.read(projectsRepoProvider);
                          if (isEdit) {
                            await repo.updateRequirement(id: existing.id, projectId: widget.projectId, qty: qty, neededBy: neededBy);
                          } else {
                            await repo.addRequirement(projectId: widget.projectId, itemId: itemId!, qty: qty, neededBy: neededBy);
                          }
                          _refresh();
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setS(() { busy = false; err = '$e'; });
                        }
                      })),
                  ]),
            ]),
          ),
        );
      }),
    );
  }

  /// Minimal "create catalog item" dialog (name + lead time) → returns it.
  Future<OptRef?> _promptNewItem() {
    final nameC = TextEditingController();
    final leadC = TextEditingController();
    return showDialog<OptRef>(context: context, builder: (dctx) {
      String? e;
      return StatefulBuilder(builder: (dctx, setD) => AlertDialog(
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
          TextButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty) { setD(() => e = 'Name required'); return; }
              final created = await ref.read(procurementRepoProvider).createItem(
                name: nameC.text.trim(), leadTimeDays: int.tryParse(leadC.text.trim()) ?? 0);
              if (dctx.mounted) Navigator.pop(dctx, created);
            },
            child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
        ],
      ));
    });
  }

  Widget _dialogField(TextEditingController c, String hint, {bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: TextField(controller: c, keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(hintText: hint, border: InputBorder.none)),
  );

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: SizedBox(width: 36, height: 52, child: Icon(icon, size: 18, color: BT.ink)));

  Widget _readonlyField(String text) => Container(
    height: 52, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14)),
    child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));

  Widget _sheetDropdown({required String? value, required List<DropdownMenuItem<String>> items,
      required ValueChanged<String?> onChanged}) => Container(
    height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, isExpanded: true, hint: const Text('Select item', style: TextStyle(color: BT.mut2, fontSize: 14)),
      icon: const Icon(Icons.expand_more_rounded, color: BT.mut2),
      style: const TextStyle(color: BT.ink, fontSize: 14, fontWeight: FontWeight.w600),
      items: items, onChanged: onChanged,
    )),
  );
}

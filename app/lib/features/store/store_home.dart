import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
import 'component_detail.dart';
import 'log_component.dart';

/// Store / Inventory shell — Inbox · Stock · Parts. Hero #2 lives here (traceability + recall).
class StoreHome extends ConsumerStatefulWidget {
  const StoreHome({super.key});
  @override
  ConsumerState<StoreHome> createState() => _StoreHomeState();
}

class _StoreHomeState extends ConsumerState<StoreHome> {
  int _tab = 0;
  static const _labels = ['Inbox', 'Stock', 'Parts'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: const [
        _InboxTab(), _StockTab(), _PartsTab(),
      ])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.local_shipping_rounded, Icons.layers_rounded, Icons.inventory_2_rounded],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        actionIcon: Icons.qr_code_scanner_rounded,
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogComponent())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 24);

Widget _storeHeader(BuildContext context, String title) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('STORE · INVENTORY',
      style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
    const SizedBox(height: 2),
    Text(title, style: display(29, w: FontWeight.w500)),
  ]),
  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
        child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
    ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Builder(builder: (_) {
        final u = sb.auth.currentUser;
        final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'S';
        return Container(width: 42, height: 42, alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF9FE0C8), Color(0xFF66C6A4)])),
          child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : 'S',
            style: display(15, w: FontWeight.w600, c: const Color(0xFF0F3A2A))));
      }),
    ),
  ])),
]);

// ───────────────────────────────────────────────────────────── INBOX

class _InboxTab extends ConsumerWidget {
  const _InboxTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comps = ref.watch(componentsProvider);
    final stock = ref.watch(stockProvider);
    return RefreshIndicator(
      onRefresh: () async { ref.invalidate(componentsProvider); return ref.refresh(stockProvider.future); },
      child: ListView(padding: _pad, children: [
        _storeHeader(context, 'Inbox'),
        const SizedBox(height: 18),
        AppCard(padding: const EdgeInsets.all(16), child: Row(children: [
          _stat('${comps.valueOrNull?.length ?? '—'}', 'Tracked'),
          _divider(),
          _stat('${stock.valueOrNull?.where((s) => s.low).length ?? '—'}', 'Low stock', color: BT.coral),
          _divider(),
          _stat('${stock.valueOrNull?.length ?? '—'}', 'Stock lines'),
        ])),
        const SectionLabel('Low stock'),
        stock.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 30),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load stock.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final low = list.where((s) => s.low).toList();
            if (low.isEmpty) {
              return const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                title: 'Stock healthy', subtitle: 'Nothing below its reorder threshold.');
            }
            return Column(children: low.map((s) => Padding(padding: const EdgeInsets.only(bottom: 11),
              child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Row(children: [
                Container(width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.coral, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFF5A2410))),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${s.quantity} ${s.unit} left · reorder', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                ])),
                const StatusPill('Low', color: BT.coral),
              ])))).toList());
          },
        ),
      ]),
    );
  }

  Widget _stat(String v, String label, {Color? color}) => Expanded(child: Column(children: [
    Text(v, style: display(24, w: FontWeight.w600, c: color)),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(color: BT.mut, fontSize: 11)),
  ]));
  Widget _divider() => Container(width: 1, height: 34, color: BT.line);
}

// ───────────────────────────────────────────────────────────── STOCK

class _StockTab extends ConsumerStatefulWidget {
  const _StockTab();
  @override
  ConsumerState<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends ConsumerState<_StockTab> {
  bool _lowOnly = false;
  @override
  Widget build(BuildContext context) {
    final stock = ref.watch(stockProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(stockProvider.future),
      child: ListView(padding: _pad, children: [
        _storeHeader(context, 'Stock'),
        const SizedBox(height: 14),
        Row(children: [
          _chip('All', !_lowOnly, () => setState(() => _lowOnly = false)),
          const SizedBox(width: 8),
          _chip('Low', _lowOnly, () => setState(() => _lowOnly = true)),
        ]),
        const SizedBox(height: 12),
        // Ask procurement to order any catalogue item — works even when the
        // inventory is empty (nothing to tap yet). Stock never changes from
        // here; it only moves on a real receive. This just raises the request.
        PrimaryButton('Request from procurement', icon: Icons.add_shopping_cart_rounded,
          onTap: () => _openRequest()),
        const SizedBox(height: 14),
        stock.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final rows = _lowOnly ? list.where((s) => s.low).toList() : list;
            if (rows.isEmpty) {
              return const EmptyState(icon: Icons.layers_rounded, tint: BT.mint,
                title: 'No stock lines', subtitle: 'Bulk items you keep in stock will show here.');
            }
            return Column(children: rows.map(_row).toList());
          },
        ),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(color: on ? BT.ink : BT.card, borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? BT.ink : BT.line)),
      child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : BT.mut))));

  Widget _row(StockRow s) {
    final color = s.low ? BT.coral : (s.quantity <= s.threshold * 2 ? BT.amber : BT.lime);
    final label = s.low ? 'Low' : (s.quantity <= s.threshold * 2 ? 'Fair' : 'OK');
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: s.itemCatalogId == null ? null : () => _openReorder(s),
      child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.inventory_2_outlined, size: 20, color: BT.ink)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text(s.category ?? 'General', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${s.quantity}${s.unit == 'pcs' ? '' : s.unit}', style: display(15, w: FontWeight.w600, c: s.low ? BT.coral : BT.ink)),
          const SizedBox(height: 3),
          StatusPill(label, color: color),
        ]),
        const SizedBox(width: 10),
        const Icon(Icons.add_shopping_cart_rounded, size: 18, color: BT.mut2),
      ]),
    )));
  }

  Future<void> _openReorder(StockRow s) async {
    final qtyCtl = TextEditingController(text: s.threshold > 0 ? '${s.threshold}' : '1');
    final noteCtl = TextEditingController();
    var sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(color: BT.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: BT.line, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            const Text('REQUEST REORDER',
              style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(s.name, style: display(22, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${s.quantity} ${s.unit} in stock · procurement will order it',
              style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 18),
            _sheetField('QUANTITY NEEDED', qtyCtl, hint: 'e.g. 20', number: true),
            const SizedBox(height: 11),
            _sheetField('NOTE (OPTIONAL)', noteCtl, hint: 'Why / for which builds'),
            const SizedBox(height: 20),
            PrimaryButton(sending ? 'Sending…' : 'Send to procurement', icon: Icons.send_rounded,
              onTap: sending ? null : () async {
                final qty = int.tryParse(qtyCtl.text.trim()) ?? 0;
                if (qty <= 0) {
                  ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                    backgroundColor: BT.coral, content: Text('Enter a quantity greater than zero.')));
                  return;
                }
                setSheet(() => sending = true);
                try {
                  await ref.read(storeRepoProvider).requestStock(
                    itemId: s.itemCatalogId!, qty: qty, note: noteCtl.text);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      backgroundColor: BT.ink, content: Text('Reorder for ${s.name} sent to procurement.')));
                  }
                } catch (e) {
                  setSheet(() => sending = false);
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                      backgroundColor: BT.coral, content: Text('Failed: $e')));
                  }
                }
              }),
          ]),
        ),
      )),
    );
  }

  Widget _sheetField(String label, TextEditingController c, {String? hint, bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: c, keyboardType: number ? TextInputType.number : null,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
        decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
          hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
      ),
    ]),
  );

  // General "raise a request" — Store picks any catalogue item (or adds a new
  // one) and asks procurement to order it. Unlike _openReorder (which starts
  // from an existing stock row), this works with an empty inventory.
  Future<void> _openRequest() async {
    final base = ref.read(itemsProvider).valueOrNull ?? <OptRef>[];
    final extra = <OptRef>[];
    String? itemId;
    final qtyCtl = TextEditingController(text: '1');
    final noteCtl = TextEditingController();
    var sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        final items = {for (final o in [...base, ...extra]) o.id: o}.values.toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(color: BT.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: BT.line, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 16),
              const Text('REQUEST FROM PROCUREMENT',
                style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Ask procurement to order an item', style: display(21, w: FontWeight.w600)),
              const SizedBox(height: 16),
              _sheetLabel('ITEM'),
              _sheetDropdown(itemId, items, (v) async {
                if (v == '__add__') {
                  final created = await _promptNewItem(sheetCtx);
                  if (created != null) {
                    setSheet(() { extra.add(created); itemId = created.id; });
                    ref.invalidate(itemsProvider);
                  }
                } else {
                  setSheet(() => itemId = v);
                }
              }),
              const SizedBox(height: 11),
              _sheetField('QUANTITY NEEDED', qtyCtl, hint: 'e.g. 20', number: true),
              const SizedBox(height: 11),
              _sheetField('NOTE (OPTIONAL)', noteCtl, hint: 'Why / for which builds'),
              const SizedBox(height: 20),
              PrimaryButton(sending ? 'Sending…' : 'Send to procurement', icon: Icons.send_rounded,
                onTap: sending ? null : () async {
                  if (itemId == null) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                      backgroundColor: BT.coral, content: Text('Pick an item first.')));
                    return;
                  }
                  final qty = int.tryParse(qtyCtl.text.trim()) ?? 0;
                  if (qty <= 0) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(
                      backgroundColor: BT.coral, content: Text('Enter a quantity greater than zero.')));
                    return;
                  }
                  setSheet(() => sending = true);
                  try {
                    await ref.read(storeRepoProvider).requestStock(
                      itemId: itemId!, qty: qty, note: noteCtl.text);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        backgroundColor: BT.ink, content: Text('Request sent to procurement.')));
                    }
                  } catch (e) {
                    setSheet(() => sending = false);
                    if (sheetCtx.mounted) {
                      ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                        backgroundColor: BT.coral, content: Text('Failed: $e')));
                    }
                  }
                }),
            ]),
          ),
        );
      }),
    );
  }

  Widget _sheetLabel(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(t, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)));

  Widget _sheetDropdown(String? value, List<OptRef> items, ValueChanged<String?> onChanged) => Container(
    height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, isExpanded: true,
      hint: const Text('Select item', style: TextStyle(color: BT.mut2, fontSize: 14, fontWeight: FontWeight.w500)),
      icon: const Icon(Icons.expand_more_rounded, color: BT.mut),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
      dropdownColor: BT.card,
      items: [
        for (final o in items) DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis)),
        const DropdownMenuItem(value: '__add__', child: Row(children: [
          Icon(Icons.add_rounded, size: 17, color: BT.ink), SizedBox(width: 6),
          Text('Add new item', style: TextStyle(fontWeight: FontWeight.w700)),
        ])),
      ],
      onChanged: onChanged,
    )),
  );

  Future<OptRef?> _promptNewItem(BuildContext ctx) {
    final nameC = TextEditingController();
    String? e;
    return showDialog<OptRef>(context: ctx, builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('New item', style: display(18, w: FontWeight.w600)),
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
}

// ───────────────────────────────────────────────────────────── PARTS

class _PartsTab extends ConsumerStatefulWidget {
  const _PartsTab();
  @override
  ConsumerState<_PartsTab> createState() => _PartsTabState();
}

class _PartsTabState extends ConsumerState<_PartsTab> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final comps = ref.watch(componentsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(componentsProvider.future),
      child: ListView(padding: _pad, children: [
        _storeHeader(context, 'Components'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 20, color: BT.mut),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search serial, model, truck…', border: InputBorder.none,
                hintStyle: TextStyle(color: BT.mut2, fontSize: 14)),
            )),
          ]),
        ),
        const SizedBox(height: 14),
        comps.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load components.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final filtered = _q.isEmpty ? list : list.where((c) =>
              c.serial.toLowerCase().contains(_q) || c.name.toLowerCase().contains(_q) ||
              c.model.toLowerCase().contains(_q) || (c.projectCode ?? '').toLowerCase().contains(_q)).toList();
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.inventory_2_outlined, tint: BT.sky,
                title: 'No components yet', subtitle: 'Log components at intake (scan icon) to track them.');
            }
            if (filtered.isEmpty) {
              return const EmptyState(icon: Icons.search_off_rounded, tint: BT.mut2,
                title: 'No matches', subtitle: 'Try a different serial, model or truck.');
            }
            return Column(children: [
              Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('${list.length} tracked components', style: const TextStyle(color: BT.mut, fontSize: 12))),
              ...filtered.map(_row),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _row(ComponentRow c) => Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComponentDetailScreen(component: c))),
    child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14), child: Row(children: [
      Container(width: 46, height: 46, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.memory_rounded, size: 21, color: Color(0xFF123040))),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.model.isEmpty ? c.name : '${c.name} · ${c.model}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text('${c.serial}${c.projectCode != null ? ' · ${c.projectCode}' : ''}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
      ])),
      StatusPill(c.warrantyEnd == null ? '—' : (c.warrantyActive ? 'In warranty' : 'Expired'),
        color: c.warrantyEnd == null ? BT.mut2 : (c.warrantyActive ? BT.lime : BT.coral)),
    ])),
  ));
}

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
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
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
      ]),
    ));
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

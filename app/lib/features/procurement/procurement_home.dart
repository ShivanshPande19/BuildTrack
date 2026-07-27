import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
import 'po_detail.dart';
import 'new_po.dart';
import 'add_vendor.dart';

/// Procurement shell — tab-based (To Order · Orders · Receive · Vendors),
/// one PillNav, in-place content switching (mirrors the Admin shell).
class ProcurementHome extends ConsumerStatefulWidget {
  const ProcurementHome({super.key});
  @override
  ConsumerState<ProcurementHome> createState() => _ProcurementHomeState();
}

class _ProcurementHomeState extends ConsumerState<ProcurementHome> {
  int _tab = 0;
  static const _labels = ['To Order', 'Orders', 'Receive', 'Vendors'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: const [
        _ToOrderTab(), _OrdersTab(), _ReceiveTab(), _VendorsTab(),
      ])),
      bottomNavigationBar: PillNav(
        icons: const [
          Icons.home_rounded, Icons.receipt_long_rounded,
          Icons.local_shipping_rounded, Icons.storefront_rounded,
        ],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _tab == 3 ? const AddVendorScreen() : const NewPoScreen())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 24);

/// Shared header: eyebrow + title + bell + avatar (bell→notifications, avatar→profile).
Widget _header(BuildContext context, String title, {int badge = 0}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('PROCUREMENT',
      style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
    const SizedBox(height: 2),
    Text(title, style: display(29, w: FontWeight.w500)),
  ]),
  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(width: 42, height: 42, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
          child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
        if (badge > 0) Positioned(top: -3, right: -3, child: Container(
          width: 19, height: 19, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.coral, shape: BoxShape.circle, border: Border.all(color: BT.bg, width: 2)),
          child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF3A1C10))))),
      ]),
    ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Builder(builder: (_) {
        final u = sb.auth.currentUser;
        final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'R';
        return Container(width: 42, height: 42, alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFC4A5EC), Color(0xFFA98FE0)])),
          child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : 'R',
            style: display(15, w: FontWeight.w600, c: const Color(0xFF31234A))));
      }),
    ),
  ])),
]);

({String label, Color color}) _duePill(int daysLeft) => daysLeft <= 0
  ? (label: 'Order today', color: BT.coral)
  : (daysLeft <= 3 ? (label: '${daysLeft}d left', color: BT.amber) : (label: 'On time', color: BT.lime));

// ───────────────────────────────────────────────────────────── TO ORDER

class _ToOrderTab extends ConsumerWidget {
  const _ToOrderTab();

  Future<void> _createPO(BuildContext context, WidgetRef ref, OrderDue d) async {
    try {
      await ref.read(procurementRepoProvider).createPO(d);
      ref.invalidate(toOrderProvider);
      ref.invalidate(purchaseOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text('PO created for ${d.itemName}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral, content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(toOrderProvider);
    final badge = items.valueOrNull?.where((d) => d.daysLeft <= 0).length ?? 0;
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(toOrderProvider.future),
      child: ListView(padding: _pad, children: [
        _header(context, 'To Order', badge: badge),
        const SizedBox(height: 20),
        items.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                title: 'Nothing to order', subtitle: 'Every requirement is ordered or on track.');
            }
            final sorted = [...list]..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
            final hero = sorted.first;
            final rest = sorted.skip(1).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _heroCard(context, ref, hero),
              if (rest.isNotEmpty) const SectionLabel('Upcoming order-by dates'),
              ...rest.map((d) => _row(context, d)),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _heroCard(BuildContext context, WidgetRef ref, OrderDue d) {
    final p = _duePill(d.daysLeft);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFCEAE2), Color(0xFFFBF6F2)]),
        borderRadius: BorderRadius.circular(BT.radiusCard),
        border: Border.all(color: const Color(0xFFF3D8CC)),
        boxShadow: const [BoxShadow(color: Color(0x11695228), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          StatusPill(p.label, color: p.color),
          Text('order by ${d.orderByDate?.toString().split(' ').first ?? '—'}',
            style: const TextStyle(fontSize: 12, color: BT.mut, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        Text(d.itemName, style: display(20, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${d.projectCode} · qty ${d.qty} · miss = delivery slips',
          style: const TextStyle(fontSize: 12.5, color: BT.mut)),
        const SizedBox(height: 14),
        PrimaryButton('Create Purchase Order', icon: Icons.add,
          onTap: () => _createPO(context, ref, d)),
      ]),
    );
  }

  Widget _row(BuildContext context, OrderDue d) {
    final p = _duePill(d.daysLeft);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text('${d.projectCode} · order by ${d.orderByDate?.toString().split(' ').first ?? '—'}',
            style: const TextStyle(color: BT.mut, fontSize: 12)),
        ])),
        const SizedBox(width: 8),
        StatusPill(p.label, color: p.color),
      ]),
    ));
  }
}

// ───────────────────────────────────────────────────────────── ORDERS

class _OrdersTab extends ConsumerStatefulWidget {
  const _OrdersTab();
  @override
  ConsumerState<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<_OrdersTab> {
  String _filter = 'all';

  ({String label, Color color}) _pill(String s) => switch (s) {
    'ordered'    => (label: 'Ordered', color: BT.sky),
    'dispatched' => (label: 'Dispatched', color: BT.amber),
    'received'   => (label: 'Received', color: BT.lime),
    'partial'    => (label: 'Partial', color: BT.amber),
    _            => (label: s, color: BT.mut2),
  };

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(purchaseOrdersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(purchaseOrdersProvider.future),
      child: ListView(padding: _pad, children: [
        _header(context, 'Orders'),
        const SizedBox(height: 14),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _chip('All', 'all'), _chip('Ordered', 'ordered'),
          _chip('Dispatched', 'dispatched'), _chip('Received', 'received'),
        ])),
        const SizedBox(height: 14),
        orders.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load orders.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final filtered = _filter == 'all' ? list : list.where((o) => o.status == _filter).toList();
            if (filtered.isEmpty) {
              return const EmptyState(icon: Icons.receipt_long_rounded, tint: BT.sky,
                title: 'No orders here', subtitle: 'Create a PO from the To Order tab.');
            }
            return Column(children: filtered.map(_orderRow).toList());
          },
        ),
      ]),
    );
  }

  Widget _chip(String label, String value) {
    final on = _filter == value;
    return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(color: on ? BT.ink : BT.card, borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? BT.ink : BT.line)),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
          color: on ? Colors.white : BT.mut)),
      ),
    ));
  }

  Widget _orderRow(PurchaseOrder o) {
    final p = _pill(o.status);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PoDetailScreen(poId: o.id, poNumber: o.poNumber))),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.poNumber, style: display(15, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${o.vendorName ?? 'Vendor'} · ${o.itemCount} item${o.itemCount == 1 ? '' : 's'}${o.projectCode != null ? ' · ${o.projectCode}' : ''}',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const SizedBox(width: 8),
          StatusPill(p.label, color: p.color),
        ]),
      ),
    ));
  }
}

// ───────────────────────────────────────────────────────────── RECEIVE

class _ReceiveTab extends ConsumerWidget {
  const _ReceiveTab();
  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(purchaseOrdersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(purchaseOrdersProvider.future),
      child: ListView(padding: _pad, children: [
        _header(context, 'Receive'),
        const SizedBox(height: 6),
        const Text('Verify items on arrival; Store then logs bills & warranty.',
          style: TextStyle(color: BT.mut, fontSize: 12.5)),
        const SizedBox(height: 8),
        orders.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final incoming = list.where((o) => o.status == 'ordered' || o.status == 'dispatched').toList();
            if (incoming.isEmpty) {
              return const Padding(padding: EdgeInsets.only(top: 20), child: EmptyState(
                icon: Icons.local_shipping_outlined, tint: BT.amber,
                title: 'Nothing incoming', subtitle: 'POs waiting to arrive will show up here.'));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Incoming'),
              ...incoming.map((o) => _receiveCard(context, ref, o)),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _receiveCard(BuildContext context, WidgetRef ref, PurchaseOrder o) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o.poNumber} · ${o.vendorName ?? 'Vendor'}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text('${o.itemCount} item${o.itemCount == 1 ? '' : 's'}${o.projectCode != null ? ' · ${o.projectCode}' : ''}',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          if (o.expectedDate != null) StatusPill(_fmt.format(o.expectedDate!), color: BT.sky),
        ]),
        const SizedBox(height: 12),
        PrimaryButton('Receive & verify', icon: Icons.check,
          onTap: () async {
            await ref.read(procurementRepoProvider).markReceived(o.id);
            ref.invalidate(purchaseOrdersProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: BT.ink, content: Text('${o.poNumber} received.')));
            }
          }),
      ]),
    ),
  );
}

// ───────────────────────────────────────────────────────────── VENDORS

class _VendorsTab extends ConsumerWidget {
  const _VendorsTab();

  Color _scoreColor(int s) => s >= 85 ? BT.lime : (s >= 70 ? BT.amber : BT.coral);
  Color _scoreFg(int s) => s >= 85 ? const Color(0xFF2F3A10) : (s >= 70 ? const Color(0xFF4A3410) : const Color(0xFF5A2410));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(vendorsProvider.future),
      child: ListView(padding: _pad, children: [
        _header(context, 'Vendors'),
        const SizedBox(height: 16),
        vendors.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load vendors.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.storefront_outlined, tint: BT.lav,
                title: 'No vendors yet', subtitle: 'Vendors you order from will appear here.');
            }
            return Column(children: list.map(_vendorRow).toList());
          },
        ),
      ]),
    );
  }

  Widget _vendorRow(VendorRow v) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.storefront_rounded, size: 21, color: BT.ink)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text('${v.category ?? 'General'} · ${v.avgLead}-day lead',
            style: const TextStyle(color: BT.mut, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(color: _scoreColor(v.reliability), borderRadius: BorderRadius.circular(999)),
          child: Text('${v.reliability}%', style: display(14, w: FontWeight.w600, c: _scoreFg(v.reliability))),
        ),
      ]),
    ),
  );
}

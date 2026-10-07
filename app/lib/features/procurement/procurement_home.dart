import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/role_header.dart';
import '../../shared/animations.dart';
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
      extendBody: true,
      body: SafeArea(bottom: false, child: TabSwitcher(index: _tab, child: const <Widget>[
        _ToOrderTab(), _OrdersTab(), _ReceiveTab(), _VendorsTab(),
      ][_tab])),
      bottomNavigationBar: PillNav(
        icons: const [
          Icons.home_rounded, Icons.receipt_long_rounded,
          Icons.local_shipping_rounded, Icons.storefront_rounded,
        ],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const NewPoScreen())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 110); // bottom clears the floating nav (extendBody)

/// Shared header. The bell shows unread notifications here like every other
/// role. It used to show the "order today" count on To Order, so it changed
/// meaning between tabs, and a rejected-PO notification could sit unread
/// behind a 0. The order-today items are already at the top of To Order.
Widget _header(BuildContext context, String title) =>
    FadeSlideIn(child: RoleHeader(role: 'procurement', eyebrow: 'Procurement', title: title));

({String label, Color color}) _duePill(int daysLeft) => daysLeft <= 0
  ? (label: 'Order today', color: BT.coral)
  : (daysLeft <= 3 ? (label: '${daysLeft}d left', color: BT.amber) : (label: 'On time', color: BT.lime));

/// Status pill for a PO — approval state comes first (it gates fulfilment),
/// then the ordered → dispatched → received lifecycle once it's approved.
({String label, Color color}) _poPill(PurchaseOrder o) {
  if (o.isRejected)      return (label: 'Rejected', color: BT.coral);
  if (o.isAwaitingPm)    return (label: 'Awaiting PM', color: BT.lav);
  if (o.isAwaitingFinal) return (label: 'Awaiting approval', color: BT.amber);
  return switch (o.status) {
    'ordered'    => (label: 'Ordered', color: BT.sky),
    'dispatched' => (label: 'Dispatched', color: BT.amber),
    'received'   => (label: 'Received', color: BT.lime),
    'partial'    => (label: 'Partial', color: BT.amber),
    _            => (label: o.status, color: BT.mut2),
  };
}

final _poMoney = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

// ───────────────────────────────────────────────────────────── TO ORDER

class _ToOrderTab extends ConsumerWidget {
  const _ToOrderTab();

  // From a To-Order alert, open the PO form pre-filled with the project + item,
  // so the buyer sets the rate/GST and it goes through approval like any PO.
  void _createPO(BuildContext context, OrderDue d) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewPoScreen(
      initialProjectId: d.projectId,
      initialItem: OptRef(d.itemCatalogId, d.itemName),
      initialQty: d.qty,
      requirementId: d.id,
    )));
  }

  // From a Store reorder request, open the PO form as a general (no-project) PO.
  void _orderStock(BuildContext context, StockRequest r) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewPoScreen(
      generalOnly: true,
      initialItem: r.itemCatalogId == null ? null : OptRef(r.itemCatalogId!, r.itemName),
      initialQty: r.qty,
      stockRequest: r,
    )));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(toOrderProvider);
    final reqs = ref.watch(stockRequestsProvider);
    final bothEmpty = (items.valueOrNull?.isEmpty ?? false) && (reqs.valueOrNull?.isEmpty ?? false);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(stockRequestsProvider);
        return ref.refresh(toOrderProvider.future);
      },
      child: ListView(padding: _pad, children: [
        _header(context, 'To Order'),
        const SizedBox(height: 20),
        // Project materials — order-by alerts (backward-scheduled requirements).
        items.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load.\n${friendlyError(e)}'),
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
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
        // Essentials — general reorder requests raised by Store (no project).
        reqs.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => ErrorCard('Could not load stock requests.\n${friendlyError(e)}'),
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Essentials to reorder · from Store'),
              ...list.map((r) => _stockReqCard(context, ref, r)),
            ]);
          },
        ),
        if (bothEmpty) const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
          title: 'Nothing to order', subtitle: 'Every requirement is ordered or on track.'),
      ]),
    );
  }

  Widget _stockReqCard(BuildContext context, WidgetRef ref, StockRequest r) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.inventory_2_outlined, size: 20, color: BT.ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text('qty ${r.qty}${r.note != null && r.note!.isNotEmpty ? ' · ${r.note}' : ''}',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const StatusPill('Store', color: BT.mint),
        ]),
        const SizedBox(height: 12),
        PrimaryButton('Order (general PO)', icon: Icons.add,
          onTap: () => _orderStock(context, r)),
      ]),
    ),
  );

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
          onTap: () => _createPO(context, d)),
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

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(purchaseOrdersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(purchaseOrdersProvider.future),
      child: ListView(padding: _pad, children: [
        _header(context, 'Orders'),
        const SizedBox(height: 14),
        FadeSlideIn(delay: Motion.stagger(1), child: ChipBar(chips: [
          _chip('All', 'all'), _chip('For approval', 'approval'),
          _chip('Ordered', 'ordered'), _chip('Dispatched', 'dispatched'), _chip('Received', 'received'),
        ])),
        const SizedBox(height: 14),
        orders.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load orders.\n${friendlyError(e)}'),
          data: (list) {
            // 'ordered'/'dispatched'/'received' only make sense for approved POs,
            // so those filters exclude ones still in approval.
            final filtered = switch (_filter) {
              'all'      => list,
              'approval' => list.where((o) => o.isPendingApproval || o.isRejected).toList(),
              _          => list.where((o) => o.isApproved && o.status == _filter).toList(),
            };
            if (filtered.isEmpty) {
              return const EmptyState(icon: Icons.receipt_long_rounded, tint: BT.sky,
                title: 'No orders here', subtitle: 'Create a PO from the To Order tab.');
            }
            return Column(children: staggered(filtered.map(_orderRow).toList()));
          },
        ),
      ]),
    );
  }

  Widget _chip(String label, String value) => AppChip(label,
    selected: _filter == value, onTap: () => setState(() => _filter = value));

  Widget _orderRow(PurchaseOrder o) {
    final p = _poPill(o);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: PressableScale(pressedScale: 0.98, haptic: true, onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PoDetailScreen(poId: o.id, poNumber: o.poNumber)));
        ref.invalidate(purchaseOrdersProvider);
      },
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(o.poNumber, style: display(15, w: FontWeight.w600)),
              if (o.amount > 0) ...[
                const SizedBox(width: 8),
                Text(_poMoney.format(o.amount), style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ]),
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
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load.\n${friendlyError(e)}'),
          data: (list) {
            // Only approved POs can move — a PO in approval isn't an order yet.
            final approved = list.where((o) => o.isApproved).toList();
            // A PO must be dispatched before it can be received.
            final ready    = approved.where((o) => o.status == 'dispatched' || o.status == 'partial').toList();
            final awaiting  = approved.where((o) => o.status == 'ordered').toList();
            if (ready.isEmpty && awaiting.isEmpty) {
              return const Padding(padding: EdgeInsets.only(top: 20), child: EmptyState(
                icon: Icons.local_shipping_outlined, tint: BT.amber,
                title: 'Nothing incoming', subtitle: 'POs waiting to arrive will show up here.'));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (ready.isNotEmpty) ...[
                const SectionLabel('Ready to receive'),
                ...ready.map((o) => _receiveCard(context, ref, o)),
              ],
              if (awaiting.isNotEmpty) ...[
                const SectionLabel('Awaiting dispatch'),
                ...awaiting.map((o) => _dispatchCard(context, ref, o)),
              ],
            ]);
          },
        ),
      ]),
    );
  }

  Widget _poHeader(PurchaseOrder o, {Widget? trailing}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${o.poNumber} · ${o.vendorName ?? 'Vendor'}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      const SizedBox(height: 2),
      Text('${o.itemCount} item${o.itemCount == 1 ? '' : 's'}${o.projectCode != null ? ' · ${o.projectCode}' : ''}',
        style: const TextStyle(color: BT.mut, fontSize: 12)),
    ])),
    if (trailing != null) trailing,
  ]);

  Widget _receiveCard(BuildContext context, WidgetRef ref, PurchaseOrder o) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _poHeader(o, trailing: o.expectedDate != null
          ? StatusPill(_fmt.format(o.expectedDate!), color: BT.sky) : null),
        const SizedBox(height: 12),
        AsyncPrimaryButton('Receive & verify', icon: Icons.check,
          onTap: () async {
            try {
              await ref.read(procurementRepoProvider).markReceived(o.id);
              ref.invalidate(purchaseOrdersProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: BT.ink, content: Text('${o.poNumber} received.')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: BT.coral, content: Text(friendlyError(e))));
              }
            }
          }),
      ]),
    ),
  );

  /// An 'ordered' PO — not receivable yet. Procurement dispatches it here
  /// (with an ETA), which moves it into "Ready to receive".
  Widget _dispatchCard(BuildContext context, WidgetRef ref, PurchaseOrder o) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _poHeader(o, trailing: const StatusPill('Ordered', color: BT.sky)),
        const SizedBox(height: 12),
        AsyncPrimaryButton('Mark dispatched', icon: Icons.local_shipping_rounded, bg: BT.ink, fg: BT.card,
          onTap: () async {
            final now = DateTime.now();
            final eta = await showDatePicker(context: context,
              initialDate: now.add(const Duration(days: 7)),
              firstDate: now, lastDate: now.add(const Duration(days: 365)),
              helpText: 'Expected arrival date');
            if (eta == null) return; // ETA required to dispatch
            try {
              await ref.read(procurementRepoProvider).markDispatched(o.id, expectedDate: eta);
              ref.invalidate(purchaseOrdersProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: BT.ink,
                  content: Text('${o.poNumber} dispatched · arriving ${_fmt.format(eta)}')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: BT.coral, content: Text(friendlyError(e))));
              }
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
        const SizedBox(height: 14),
        // Same fix as Admin → Team: the create action is a compact pill beside
        // the section title, not a full-width ink bar above the list.
        FadeSlideIn(delay: Motion.stagger(1), child: Row(children: [
          const Expanded(child: Text('Who you buy from', style: TextStyle(color: BT.mut, fontSize: 12.5))),
          PillAction('Add vendor', icon: Icons.add_business_rounded,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddVendorScreen()));
              ref.invalidate(vendorsProvider);
            }),
        ])),
        const SizedBox(height: 14),
        vendors.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load vendors.\n${friendlyError(e)}'),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.storefront_outlined, tint: BT.lav,
                title: 'No vendors yet', subtitle: 'Vendors you order from will appear here.');
            }
            return Column(children: staggered(list.map(_vendorRow).toList()));
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

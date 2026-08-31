import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/animations.dart';
import '../common/notifications.dart';
import 'new_ticket.dart';
import 'ticket_detail.dart';
import 'truck_history.dart';

/// Service shell — Tickets · Trucks · Warranty · Profile.
///
/// The after-sales role: picks up client requests on delivered trucks, triages
/// them against an SLA, sends a technician, and closes the loop with the client.
class ServiceHome extends ConsumerStatefulWidget {
  const ServiceHome({super.key});
  @override
  ConsumerState<ServiceHome> createState() => _ServiceHomeState();
}

class _ServiceHomeState extends ConsumerState<ServiceHome> {
  int _tab = 0;
  static const _labels = ['Tickets', 'Trucks', 'Warranty', 'Profile'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: TabSwitcher(index: _tab, child: const <Widget>[
        _TicketsTab(), _TrucksTab(), _WarrantyTab(), _ProfileTab(),
      ][_tab])),
      bottomNavigationBar: PillNav(
        icons: const [
          Icons.headset_mic_rounded, Icons.local_shipping_rounded,
          Icons.shield_rounded, Icons.person_rounded,
        ],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewTicketScreen())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 24);
final _dayFmt = DateFormat('d MMM');

Widget svHeader(BuildContext context, String title) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('SERVICE · SUPPORT',
      style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
    const SizedBox(height: 2),
    Text(title, style: display(29, w: FontWeight.w500)),
  ]),
  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
        child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
    ),
    const SizedBox(width: 10),
    Builder(builder: (_) {
      final u = sb.auth.currentUser;
      final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'S';
      return Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFF2A585), Color(0xFFE07F5A)])),
        child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : 'S',
          style: display(15, w: FontWeight.w600, c: const Color(0xFF5A2410))));
    }),
  ])),
]);

/// Ticket status → pill. Shared with the ticket detail + truck history screens.
({String label, Color color}) ticketPill(String s) => switch (s) {
  'open'        => (label: 'Open', color: BT.coral),
  'in_progress' => (label: 'In progress', color: BT.amber),
  'resolved'    => (label: 'Resolved', color: BT.lime),
  'closed'      => (label: 'Closed', color: BT.mut2),
  _             => (label: s, color: BT.mut2),
};

Color priorityColor(String p) => switch (p) {
  'high' => BT.coral, 'medium' => BT.amber, _ => BT.sky,
};

String categoryLabel(String c) => switch (c) {
  'equipment'  => 'Equipment',
  'electrical' => 'Electrical',
  'cosmetic'   => 'Cosmetic',
  _            => 'Other',
};

// ───────────────────────────────────────────────────────────── TICKETS (sv1)

class _TicketsTab extends ConsumerStatefulWidget {
  const _TicketsTab();
  @override
  ConsumerState<_TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends ConsumerState<_TicketsTab> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(serviceTicketsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(serviceTicketsProvider.future),
      child: ListView(padding: _pad, children: [
        svHeader(context, 'Tickets'),
        const SizedBox(height: 18),
        tickets.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 70),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load tickets.\n${friendlyError(e)}',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final open = list.where((t) => t.isOpen).toList();
            final overdue = open.where((t) => t.isOverdue).length;
            final resolvedToday = list.where((t) =>
              t.resolvedAt != null &&
              DateTime.now().difference(t.resolvedAt!).inDays == 0).length;

            final shown = switch (_filter) {
              'open'     => open,
              'overdue'  => open.where((t) => t.isOverdue).toList(),
              'resolved' => list.where((t) => t.isResolved).toList(),
              _          => list,
            };

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // open / overdue / resolved-today
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  _stat('${open.length}', 'Open', BT.coral),
                  _divider(),
                  _stat('$overdue', 'Overdue', overdue > 0 ? BT.coral : BT.mut2),
                  _divider(),
                  _stat('$resolvedToday', 'Fixed today', BT.lime),
                ]),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                _chip('Open ${open.length}', 'open'),
                if (overdue > 0) _chip('Overdue $overdue', 'overdue', tint: BT.coral),
                _chip('Resolved', 'resolved'),
                _chip('All ${list.length}', 'all'),
              ])),
              const SizedBox(height: 14),
              if (list.isEmpty)
                const EmptyState(icon: Icons.support_agent_rounded, tint: BT.coral,
                  title: 'No tickets yet',
                  subtitle: 'Requests raised by clients on delivered trucks land here, '
                            'newest deadline first.')
              else if (shown.isEmpty)
                const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                  title: 'Nothing here', subtitle: 'No tickets match this filter.')
              else
                ...shown.map((t) => ticketCard(context, ref, t)),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _stat(String value, String label, Color c) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: display(30, w: FontWeight.w600, c: c)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: BT.mut, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _divider() => Container(width: 1, height: 38, color: BT.line,
    margin: const EdgeInsets.symmetric(horizontal: 12));

  Widget _chip(String label, String value, {Color? tint}) {
    final on = _filter == value;
    return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(color: on ? BT.ink : (tint ?? BT.card),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? BT.ink : (tint ?? BT.line))),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
          color: on ? Colors.white : (tint != null ? BT.ink : BT.mut))),
      ),
    ));
  }
}

/// One ticket row — used by the queue and by a truck's service history.
Widget ticketCard(BuildContext context, WidgetRef ref, ServiceTicket t) => Padding(
  padding: const EdgeInsets.only(bottom: 11),
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketDetailScreen(ticketId: t.id))).then((_) {
        ref.invalidate(serviceTicketsProvider);
        ref.invalidate(deliveredTrucksProvider);
      }),
    child: AppCard(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: priorityColor(t.priority),
              borderRadius: BorderRadius.circular(13)),
            child: Icon(switch (t.category) {
              'electrical' => Icons.electrical_services_rounded,
              'cosmetic'   => Icons.brush_rounded,
              'equipment'  => Icons.kitchen_rounded,
              _            => Icons.build_rounded,
            }, size: 20, color: BT.ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.description == null || t.description!.isEmpty
                  ? categoryLabel(t.category) : t.description!,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text([
              if (t.projectCode != null) t.projectCode!,
              if (t.clientName != null) t.clientName!,
              t.number,
            ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 11.5)),
          ])),
          const SizedBox(width: 8),
          // SLA countdown is the whole point of the queue
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.isResolved
                ? BT.card2
                : (t.isOverdue ? BT.coral : (t.priority == 'high' ? BT.amber : BT.card2)),
              borderRadius: BorderRadius.circular(999)),
            child: Text(t.slaLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BT.ink)),
          ),
        ]),
        if (t.isResolved && t.resolutionNote != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.check_circle_rounded, size: 14, color: BT.mut2),
            const SizedBox(width: 6),
            Expanded(child: Text(t.resolutionNote!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 11.5))),
          ]),
        ],
      ]),
    ),
  ),
);

// ───────────────────────────────────────────────────────── TRUCKS (sv5)

class _TrucksTab extends ConsumerWidget {
  const _TrucksTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trucks = ref.watch(deliveredTrucksProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(deliveredTrucksProvider.future),
      child: ListView(padding: _pad, children: [
        svHeader(context, 'Delivered'),
        const SizedBox(height: 18),
        trucks.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 70),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load trucks.\n${friendlyError(e)}',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.local_shipping_outlined, tint: BT.coral,
                title: 'No trucks in service yet',
                subtitle: 'A build appears here once its project manager marks it '
                          'delivered. After-sales support starts from that point.');
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${list.length} truck${list.length == 1 ? '' : 's'} in service',
                style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              ...list.map((d) => Padding(padding: const EdgeInsets.only(bottom: 11),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TruckHistoryScreen(projectId: d.project.id))),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${d.project.code} · ${d.project.name}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                        const SizedBox(height: 3),
                        Text([
                          if (d.deliveredOn != null) 'Delivered ${_dayFmt.format(d.deliveredOn!)}',
                          if (d.openTickets > 0)
                            '${d.openTickets} open ticket${d.openTickets == 1 ? '' : 's'}'
                          else 'no open tickets',
                        ].join(' · '), style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                      ])),
                      const SizedBox(width: 8),
                      if (d.openTickets > 0)
                        StatusPill('${d.openTickets} open', color: BT.coral)
                      else if (d.expiringParts > 0)
                        const StatusPill('Wty soon', color: BT.amber)
                      else
                        const StatusPill('Healthy', color: BT.lime),
                    ]),
                  ),
                ))),
            ]);
          },
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────── WARRANTY (sv7)

class _WarrantyTab extends ConsumerStatefulWidget {
  const _WarrantyTab();
  @override
  ConsumerState<_WarrantyTab> createState() => _WarrantyTabState();
}

class _WarrantyTabState extends ConsumerState<_WarrantyTab> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ({String label, Color color}) _pill(String state) => switch (state) {
    'active'   => (label: 'In warranty', color: BT.lime),
    'expiring' => (label: 'Expiring', color: BT.amber),
    'expired'  => (label: 'Expired', color: BT.coral),
    _          => (label: 'No warranty', color: BT.mut2),
  };

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(warrantySearchProvider(_query));
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(warrantySearchProvider(_query).future),
      child: ListView(padding: _pad, children: [
        svHeader(context, 'Warranty'),
        const SizedBox(height: 16),

        // search: serial / model / truck
        Container(
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BT.line)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 20, color: BT.mut),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => setState(() => _query = v.trim()),
              decoration: const InputDecoration(
                hintText: 'Serial, model or truck…', border: InputBorder.none,
                hintStyle: TextStyle(color: BT.mut2, fontSize: 14)),
            )),
            if (_search.text.isNotEmpty) GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () { _search.clear(); setState(() => _query = ''); },
              child: const Padding(padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 18, color: BT.mut)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        const Padding(padding: EdgeInsets.only(left: 4),
          child: Text('Press enter to search. Warranty is tracked per serial from intake.',
            style: TextStyle(color: BT.mut2, fontSize: 11.5))),
        const SizedBox(height: 14),

        results.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 50),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Lookup failed.\n${friendlyError(e)}',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(icon: Icons.shield_outlined, tint: BT.sky,
                title: _query.isEmpty ? 'No parts logged yet' : 'Nothing found',
                subtitle: _query.isEmpty
                  ? 'Parts appear here once Store logs them with a serial and warranty.'
                  : 'No part matches "$_query". Try a serial, a model or a truck code.');
            }
            return Column(children: list.map((w) {
              final p = _pill(w.state);
              return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(width: 42, height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.color.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.memory_rounded, size: 20, color: BT.ink)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(w.model.isEmpty ? w.itemName : '${w.itemName} · ${w.model}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text([
                      w.serial,
                      if (w.projectCode.isNotEmpty) w.projectCode,
                      if (w.vendorName.isNotEmpty) w.vendorName,
                    ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                  ])),
                  const SizedBox(width: 8),
                  StatusPill(w.warrantyEnd == null ? p.label : w.label, color: p.color),
                ]),
              ));
            }).toList());
          },
        ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────── PROFILE (sv9)

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = sb.auth.currentUser;
    final name = (u?.userMetadata?['full_name'] as String?) ?? u?.email?.split('@').first ?? 'Service';
    final email = u?.email ?? '';
    final tickets = ref.watch(serviceTicketsProvider).valueOrNull ?? const <ServiceTicket>[];
    final mine = tickets.where((t) => t.assignedTo == u?.id).toList();
    final openMine = mine.where((t) => t.isOpen).length;
    final fixedToday = tickets.where((t) =>
      t.resolvedAt != null && DateTime.now().difference(t.resolvedAt!).inDays == 0).length;

    return ListView(padding: _pad, children: [
      Text('Profile', style: display(29, w: FontWeight.w500)),
      const SizedBox(height: 18),
      AppCard(padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(children: [
          Container(width: 74, height: 74, alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFF2A585), Color(0xFFE07F5A)])),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S',
              style: display(26, w: FontWeight.w600, c: const Color(0xFF5A2410)))),
          const SizedBox(height: 14),
          Text(name, style: display(20, w: FontWeight.w600)),
          const SizedBox(height: 8),
          const StatusPill('Service & Support', color: BT.coral),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(email, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          Text('$openMine assigned to me · $fixedToday resolved today',
            style: const TextStyle(color: BT.mut, fontSize: 12.5)),
        ])),
      const SectionLabel('Account'),
      _row(Icons.notifications_none_rounded, 'Notifications',
        () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
      _row(Icons.person_outline_rounded, 'My details',
        () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Account details — coming soon')))),
      const SizedBox(height: 20),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => sb.auth.signOut().then((_) {
          if (context.mounted) context.go('/login');
        }),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.logout_rounded, size: 19, color: BT.coral)),
          const SizedBox(width: 15),
          const Text('Log out', style: TextStyle(fontSize: 14.5,
            fontWeight: FontWeight.w600, color: BT.coral)),
        ]),
      ),
    ]);
  }

  Widget _row(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 19, color: BT.ink)),
        const SizedBox(width: 15),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ])),
  );
}

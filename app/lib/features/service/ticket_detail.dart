import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'service_home.dart' show ticketPill, priorityColor, categoryLabel;
import 'resolve_ticket.dart';
import 'schedule_visit.dart';

/// Service — ticket detail (sv2): the issue, the part it points at and its
/// warranty, the visit booked for it, and the two actions that move it forward.
class TicketDetailScreen extends ConsumerWidget {
  final String ticketId;
  const TicketDetailScreen({super.key, required this.ticketId});

  static final _fmt = DateFormat('d MMM, h:mm a');
  static final _day = DateFormat('d MMM yyyy');

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'raised ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'raised ${d.inHours}h ago';
    return 'raised ${d.inDays}d ago';
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(serviceTicketProvider(ticketId));
    ref.invalidate(ticketVisitsProvider(ticketId));
    ref.invalidate(serviceTicketsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(serviceTicketProvider(ticketId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            ticket.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => Column(children: [
                _backRow(context, null),
                const SizedBox(height: 16),
                AppCard(child: Text('Could not load this ticket.\n${friendlyError(e)}',
                  style: const TextStyle(color: BT.coral, fontSize: 13))),
              ]),
              data: (t) => _content(context, ref, t),
            ),
          ],
        ),
      )),
    );
  }

  Widget _backRow(BuildContext context, ServiceTicket? t) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: Container(width: 42, height: 42, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle,
            border: Border.all(color: BT.line)),
          child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
      ),
      if (t != null) Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: t.isResolved ? BT.card2 : (t.isOverdue ? BT.coral : BT.amber),
          borderRadius: BorderRadius.circular(999)),
        child: Text(t.isResolved ? ticketPill(t.status).label : 'SLA · ${t.slaLabel}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BT.ink)),
      ),
    ]);

  Widget _content(BuildContext context, WidgetRef ref, ServiceTicket t) {
    final pill = ticketPill(t.status);
    final names = <String, String>{
      for (final m in (ref.watch(membersProvider).valueOrNull ?? <Member>[])) m.id: m.name
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _backRow(context, t),
      const SizedBox(height: 14),
      Text(t.description == null || t.description!.isEmpty
            ? categoryLabel(t.category) : t.description!,
        style: display(25, w: FontWeight.w600)),
      const SizedBox(height: 5),
      Text([
        t.number,
        if (t.projectCode != null) t.projectCode!,
        if (t.clientName != null) t.clientName!,
        _ago(t.createdAt),
      ].where((s) => s.isNotEmpty).join(' · '),
        style: const TextStyle(color: BT.mut, fontSize: 12.5)),
      const SizedBox(height: 14),

      Wrap(spacing: 8, runSpacing: 8, children: [
        StatusPill(pill.label, color: pill.color),
        StatusPill('${t.priority} priority', color: priorityColor(t.priority)),
        StatusPill(categoryLabel(t.category), color: BT.card2),
      ]),

      // the client's words
      if (t.description != null && t.description!.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppCard(padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.format_quote_rounded, size: 18, color: BT.mut2),
            const SizedBox(width: 10),
            Expanded(child: Text(t.description!,
              style: const TextStyle(fontSize: 14, height: 1.45))),
          ])),
      ],

      // who's on it
      const SectionLabel('Assigned to'),
      _assigneeCard(context, ref, t, names),

      // the part it points at + whether it's still covered
      if (t.linkedComponentId != null) ...[
        const SectionLabel('Linked component'),
        ref.watch(ticketComponentProvider(t.linkedComponentId!)).when(
          loading: () => const AppCard(child: Center(child: Padding(
            padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: BT.ink)))),
          error: (e, _) => AppCard(child: Text('Could not load the part.\n${friendlyError(e)}',
            style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          data: (w) => w == null
            ? const AppCard(child: Text('That part is no longer in the system.',
                style: TextStyle(color: BT.mut, fontSize: 13)))
            : AppCard(padding: const EdgeInsets.all(16), child: Row(children: [
                Container(width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.mint.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.memory_rounded, size: 21, color: BT.ink)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.model.isEmpty ? w.itemName : '${w.itemName} · ${w.model}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text([w.serial, if (w.vendorName.isNotEmpty) w.vendorName].join(' · '),
                    style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                  if (w.warrantyEnd != null) ...[
                    const SizedBox(height: 2),
                    Text('Warranty until ${_day.format(w.warrantyEnd!)}',
                      style: const TextStyle(color: BT.mut2, fontSize: 11)),
                  ],
                ])),
                const SizedBox(width: 8),
                StatusPill(w.label, color: switch (w.state) {
                  'active' => BT.lime, 'expiring' => BT.amber,
                  'expired' => BT.coral, _ => BT.mut2,
                }),
              ])),
        ),
      ],

      // visits booked against it
      _visits(context, ref, t, names),

      // outcome
      if (t.isResolved) ...[
        const SectionLabel('Resolution'),
        AppCard(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 38, height: 38, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.verified_rounded, size: 19, color: BT.ink)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(switch (t.resolutionType) {
                  'warranty_replace' => 'Replaced under warranty',
                  'repair'           => 'Repaired on-site',
                  'remote_guide'     => 'Guided remotely',
                  _                  => 'Resolved',
                }, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (t.resolvedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(_fmt.format(t.resolvedAt!),
                    style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                ],
              ])),
            ]),
            if (t.resolutionNote != null && t.resolutionNote!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.resolutionNote!, style: const TextStyle(fontSize: 13.5, height: 1.4)),
            ],
          ])),
      ],

      const SizedBox(height: 18),
      _actions(context, ref, t),
    ]);
  }

  Widget _assigneeCard(BuildContext context, WidgetRef ref, ServiceTicket t,
      Map<String, String> names) {
    final who = t.assignedTo == null ? null : (names[t.assignedTo] ?? 'Assigned');
    final canAct = !t.isResolved;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !canAct ? null : () => _pickTechnician(context, ref, t),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: who == null ? BT.card2 : BT.coral,
              borderRadius: BorderRadius.circular(12)),
            child: Icon(who == null ? Icons.person_off_rounded : Icons.engineering_rounded,
              size: 19, color: BT.ink)),
          const SizedBox(width: 12),
          Expanded(child: Text(who ?? 'Nobody yet — tap to assign',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
              color: who == null ? BT.mut : BT.ink))),
          if (canAct) const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
        ]),
      ),
    );
  }

  Widget _visits(BuildContext context, WidgetRef ref, ServiceTicket t,
      Map<String, String> names) {
    final visits = ref.watch(ticketVisitsProvider(ticketId)).valueOrNull ?? const <ServiceVisitRow>[];
    if (visits.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Visits'),
      ...visits.map((v) {
        final tech = v.technicianId == null ? null : names[v.technicianId];
        final c = switch (v.status) {
          'scheduled' => BT.amber, 'done' => BT.lime, _ => BT.mut2,
        };
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(width: 38, height: 38, alignment: Alignment.center,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.event_rounded, size: 18, color: BT.ink)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.scheduledDate == null ? 'Visit' : _fmt.format(v.scheduledDate!.toLocal()),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text([
                if (tech != null) tech,
                if (v.note != null && v.note!.isNotEmpty) v.note!,
              ].join(' · '), maxLines: 2,
                style: const TextStyle(color: BT.mut, fontSize: 11.5)),
            ])),
            StatusPill(v.status, color: c),
          ]),
        ));
      }),
    ]);
  }

  Widget _actions(BuildContext context, WidgetRef ref, ServiceTicket t) {
    if (t.status == 'closed') {
      return const AppCard(child: Row(children: [
        Icon(Icons.lock_outline_rounded, size: 18, color: BT.mut),
        SizedBox(width: 10),
        Expanded(child: Text('This ticket is closed.',
          style: TextStyle(color: BT.mut, fontSize: 13))),
      ]));
    }
    if (t.status == 'resolved') {
      return PrimaryButton('Close ticket', icon: Icons.lock_rounded, bg: BT.card2,
        onTap: () async {
          try {
            await ref.read(serviceRepoProvider).close(t.id);
            await _refresh(ref);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: BT.ink, content: Text('${t.number} closed')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: BT.coral, content: Text(friendlyError(e))));
            }
          }
        });
    }
    return Row(children: [
      Expanded(child: PrimaryButton('Schedule visit', icon: Icons.event_rounded, bg: BT.card2,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ScheduleVisitScreen(ticket: t))).then((_) => _refresh(ref)))),
      const SizedBox(width: 11),
      Expanded(child: PrimaryButton('Resolve', icon: Icons.check_rounded,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ResolveTicketScreen(ticket: t))).then((_) => _refresh(ref)))),
    ]);
  }

  /// Triage sheet — service + workshop members only (the DB enforces this too).
  void _pickTechnician(BuildContext context, WidgetRef ref, ServiceTicket t) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer(builder: (ctx, r, _) {
        final techs = r.watch(techniciansProvider);
        Future<void> apply(String? uid) async {
          try {
            await r.read(serviceRepoProvider).assign(t.id, uid);
            await _refresh(r);
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                backgroundColor: BT.coral, content: Text(friendlyError(e))));
            }
          }
        }
        return Container(
          decoration: const BoxDecoration(color: BT.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
              Text('Assign ${t.number}', style: display(19, w: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Service and workshop members can take a ticket.',
                style: TextStyle(color: BT.mut, fontSize: 12.5)),
              const SizedBox(height: 14),
              techs.when(
                loading: () => const Padding(padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: BT.ink))),
                error: (e, _) => Text('Could not load the team.\n${friendlyError(e)}',
                  style: const TextStyle(color: BT.coral, fontSize: 13)),
                data: (list) => list.isEmpty
                  ? const EmptyState(icon: Icons.people_outline_rounded, tint: BT.coral,
                      title: 'No technicians',
                      subtitle: 'Add service or workshop members first.')
                  : Column(children: [
                      ...list.map((m) {
                        final selected = m.id == t.assignedTo;
                        return Padding(padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => apply(m.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(color: BT.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: selected ? BT.ink : BT.line,
                                  width: selected ? 1.5 : 1)),
                              child: Row(children: [
                                Container(width: 38, height: 38, alignment: Alignment.center,
                                  decoration: BoxDecoration(color: roleColor(m.role),
                                    shape: BoxShape.circle),
                                  child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: BT.ink))),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name.isEmpty ? m.email : m.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 1),
                                    Text(m.role, style: const TextStyle(color: BT.mut, fontSize: 12)),
                                  ])),
                                if (selected) const Icon(Icons.check_circle_rounded,
                                  color: BT.ink, size: 20),
                              ]),
                            ),
                          ));
                      }),
                      if (t.assignedTo != null) Padding(padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => apply(null),
                          child: Container(width: double.infinity, alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
                              borderRadius: BorderRadius.circular(16)),
                            child: const Text('Unassign',
                              style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700)),
                          ),
                        )),
                    ]),
              ),
            ])),
        );
      }),
    );
  }
}

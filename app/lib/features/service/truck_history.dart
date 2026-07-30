import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'service_home.dart' show ticketCard;

/// Service — truck history (sv6): one delivered truck, its warranty position
/// and every request ever raised against it.
class TruckHistoryScreen extends ConsumerWidget {
  final String projectId;
  const TruckHistoryScreen({super.key, required this.projectId});

  static final _day = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(truckHistoryProvider(projectId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(truckHistoryProvider(projectId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle,
                    border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              if (history.valueOrNull != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: BT.line)),
                child: Text(history.value!.project.code,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            history.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 70),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load this truck.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (h) {
                final wEnd = h.earliestWarrantyEnd;
                final wDays = wEnd?.difference(DateTime.now()).inDays;
                final open = h.tickets.where((t) => t.isOpen).length;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.project.name, style: display(27, w: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text([
                    if (h.deliveredOn != null) 'Delivered ${_day.format(h.deliveredOn!)}',
                    if (h.daysInService != null) 'in service ${h.daysInService} days',
                  ].join(' · '), style: const TextStyle(color: BT.mut, fontSize: 13)),
                  const SizedBox(height: 16),

                  // client · parts tracked · warranty
                  AppCard(padding: const EdgeInsets.all(18), child: Row(children: [
                    _fact('Client', h.clientName ?? '—'),
                    _divider(),
                    _fact('Parts', '${h.componentCount} tracked'),
                    _divider(),
                    _fact('Warranty', wDays == null
                        ? '—'
                        : wDays < 0
                          ? 'Expired'
                          : wDays >= 60 ? '${(wDays / 30).floor()} mo left' : '${wDays}d left'),
                  ])),

                  const SectionLabel('Service history'),
                  if (h.tickets.isEmpty)
                    const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                      title: 'No issues raised',
                      subtitle: 'This truck has had a clean run since delivery.')
                  else ...[
                    Padding(padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Text('${h.tickets.length} request${h.tickets.length == 1 ? '' : 's'}'
                                  '${open > 0 ? ' · $open still open' : ''}',
                        style: const TextStyle(color: BT.mut, fontSize: 12))),
                    ...h.tickets.map((t) => ticketCard(context, ref, t)),
                  ],
                ]);
              },
            ),
          ],
        ),
      )),
    );
  }

  Widget _fact(String label, String value) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: BT.mut, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
    ]),
  );

  Widget _divider() => Container(width: 1, height: 34, color: BT.line,
    margin: const EdgeInsets.symmetric(horizontal: 12));
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
import 'truck_view.dart';

/// Client entry — My Trucks (handles multiple projects per client).
class ClientHome extends ConsumerWidget {
  const ClientHome({super.key});

  ({String label, Color color}) _status(String s) => switch (s) {
    'on_track' => (label: 'On track', color: BT.lime),
    'at_risk'  => (label: 'At-risk', color: BT.amber),
    'delayed'  => (label: 'Delayed', color: BT.coral),
    'delivered'=> (label: 'Delivered', color: BT.ink),
    _          => (label: s, color: BT.mut2),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trucks = ref.watch(myTrucksProvider);
    final u = sb.auth.currentUser;
    final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'C';
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(myTrucksProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('WELCOME BACK', style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('My Trucks', style: display(29, w: FontWeight.w500)),
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
                  child: Container(width: 42, height: 42, alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3C3DD), Color(0xFFF2A585)])),
                    child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : 'C', style: display(15, w: FontWeight.w600, c: const Color(0xFF5A2438)))),
                ),
              ])),
            ]),
            const SizedBox(height: 18),
            trucks.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load your trucks.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.local_shipping_outlined, tint: BT.pink,
                    title: 'No trucks yet', subtitle: 'Your builds with Azimuth will appear here.');
                }
                return Column(children: [
                  Padding(padding: const EdgeInsets.only(left: 2, bottom: 10),
                    child: Align(alignment: Alignment.centerLeft,
                      child: Text('You have ${list.length} truck${list.length == 1 ? '' : 's'} with Azimuth',
                        style: const TextStyle(color: BT.mut, fontSize: 13)))),
                  ...list.map((p) => _truckCard(context, p)),
                ]);
              },
            ),
          ],
        ),
      )),
    );
  }

  Widget _truckCard(BuildContext context, Project p) {
    final s = _status(p.status);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TruckView(project: p))),
      child: AppCard(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          const SizedBox(width: 8),
          StatusPill(s.label, color: s.color, dark: p.status == 'delivered'),
        ]),
        const SizedBox(height: 3),
        Text(p.code, style: const TextStyle(color: BT.mut, fontSize: 12)),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
          value: p.progressPct.clamp(0, 100) / 100, minHeight: 8,
          backgroundColor: BT.track, valueColor: const AlwaysStoppedAnimation(BT.lime))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${p.progressPct}% built', style: const TextStyle(color: BT.mut, fontSize: 12)),
          const Row(children: [Text('View', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)), Icon(Icons.chevron_right_rounded, size: 16)]),
        ]),
      ])),
    ));
  }
}

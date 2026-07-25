import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'onboard_project.dart';
import 'team.dart';

/// Admin — Fleet Monitor. Live data from Supabase (projects + v_order_due).
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(fleetProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              // header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('OWNER · ADMIN',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Fleet Monitor', style: display(29, w: FontWeight.w500)),
                ]),
                GestureDetector(
                  onTap: () => sb.auth.signOut().then((_) => context.go('/login')),
                  child: const CircleAvatar(radius: 21, backgroundColor: BT.ink,
                    child: Text('A', style: TextStyle(color: BT.lime, fontWeight: FontWeight.w700))),
                ),
              ]),
              const SizedBox(height: 20),
              fleet.when(
                loading: () => const Padding(padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator(color: BT.ink))),
                error: (e, _) => AppCard(child: Text('Could not load fleet.\n$e',
                  style: const TextStyle(color: BT.coral, fontSize: 13))),
                data: (f) => _content(context, f),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: PillNav(
        icons: const [Icons.home_rounded, Icons.grid_view_rounded, Icons.people_rounded, Icons.bar_chart_rounded],
        active: 0, activeLabel: 'Home',
        onTap: (i) {
          if (i == 2) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamScreen()));
        },
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OnboardProject()))),
    );
  }

  Widget _content(BuildContext context, FleetData f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // build-status card
      AppCard(
        color: BT.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BUILD STATUS · THIS WEEK',
            style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${f.total}', style: display(52, w: FontWeight.w500)),
            const SizedBox(width: 8),
            const Padding(padding: EdgeInsets.only(bottom: 8),
              child: Text('active\nbuilds', style: TextStyle(color: BT.mut, fontSize: 13))),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            StatusPill('${f.onTrack} on-track', color: BT.lime),
            StatusPill('${f.atRisk} at-risk', color: BT.amber),
            StatusPill('${f.delayed} delayed', color: BT.coral),
          ]),
        ]),
      ),
      const SectionLabel('Needs attention'),
      if (f.urgent.isEmpty)
        const AppCard(child: Text('All order-by dates are on track. 🎉',
          style: TextStyle(color: BT.mut, fontSize: 13)))
      else
        ...f.urgent.map((d) => Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 3),
                Text('${d.projectCode} · order-by ${d.orderByDate?.toString().split(' ').first ?? '—'}',
                  style: const TextStyle(color: BT.mut, fontSize: 12.5)),
              ])),
              StatusPill(
                d.daysLeft <= 0 ? 'Order today' : '${d.daysLeft}d left',
                color: d.daysLeft <= 0 ? BT.coral : BT.amber),
            ]),
          ),
        )),
    ],
  );
}

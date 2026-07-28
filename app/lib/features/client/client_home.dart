import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
import 'raise_request.dart';
import 'truck_3d.dart';
import 'truck_detail.dart';

/// Client shell — global navbar: My Trucks · Support · Profile.
/// Everything about a truck (progress, stage, photos, docs) lives inside its detail.
class ClientHome extends ConsumerStatefulWidget {
  const ClientHome({super.key});
  @override
  ConsumerState<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends ConsumerState<ClientHome> {
  int _tab = 0;
  static const _labels = ['My Trucks', 'Support', 'Profile'];

  void _raise(List<Project> trucks) {
    if (trucks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.coral, content: Text('No truck to raise a request for.')));
      return;
    }
    if (trucks.length == 1) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaiseRequest(projectId: trucks.first.id)));
      return;
    }
    showModalBottomSheet<void>(context: context, backgroundColor: Colors.transparent, builder: (ctx) => Container(
      decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
        Text('Which truck?', style: display(19, w: FontWeight.w600)),
        const SizedBox(height: 12),
        ...trucks.map((t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaiseRequest(projectId: t.id))); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
            child: Row(children: [Expanded(child: Text('${t.code} · ${t.name}', style: const TextStyle(fontWeight: FontWeight.w600))), const Icon(Icons.chevron_right_rounded, color: BT.mut2)])),
        ))),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final trucks = ref.watch(myTrucksProvider).valueOrNull ?? const <Project>[];
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: [
        _trucksTab(), _supportTab(), _profileTab(),
      ])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.local_shipping_rounded, Icons.headset_mic_rounded, Icons.person_rounded],
        active: _tab, activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: () => _raise(trucks),
      ),
    );
  }

  Widget _bell() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
    child: Container(width: 42, height: 42, alignment: Alignment.center,
      decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
      child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
  );

  ({String label, Color color}) _status(String s) => switch (s) {
    'on_track' => (label: 'On track', color: BT.lime),
    'at_risk'  => (label: 'At-risk', color: BT.amber),
    'delayed'  => (label: 'Delayed', color: BT.coral),
    'delivered'=> (label: 'Delivered', color: BT.ink),
    _          => (label: s, color: BT.mut2),
  };

  // ── MY TRUCKS ─────────────────────────────────────────────
  Widget _trucksTab() {
    final trucks = ref.watch(myTrucksProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myTrucksProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WELCOME BACK', style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('My Trucks', style: display(29, w: FontWeight.w500)),
          ]),
          Padding(padding: const EdgeInsets.only(top: 4), child: _bell()),
        ]),
        const SizedBox(height: 18),
        trucks.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load your trucks.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.local_shipping_outlined, tint: BT.pink, title: 'No trucks yet', subtitle: 'Your builds with Azimuth will appear here.');
            }
            return Column(children: [
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 2, bottom: 10),
                child: Text('You have ${list.length} truck${list.length == 1 ? '' : 's'} with Azimuth', style: const TextStyle(color: BT.mut, fontSize: 13)))),
              ...list.map(_truckCard),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _truckCard(Project p) {
    final s = _status(p.status);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientTruckDetail(project: p))),
      child: AppCard(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 3D design preview — prototype shows a demo truck on every card.
        // In production this renders only once the design is approved, using
        // the approved design version's .glb URL.
        Truck3DPreview(glbUrl: kDemoTruckGlb, label: p.name, height: 190),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          const SizedBox(width: 8),
          StatusPill(s.label, color: s.color, dark: p.status == 'delivered'),
        ]),
        const SizedBox(height: 3),
        Text(p.code, style: const TextStyle(color: BT.mut, fontSize: 12)),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
          value: p.progressPct.clamp(0, 100) / 100, minHeight: 8, backgroundColor: BT.track, valueColor: const AlwaysStoppedAnimation(BT.lime))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${p.progressPct}% built', style: const TextStyle(color: BT.mut, fontSize: 12)),
          const Row(children: [Text('View', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)), Icon(Icons.chevron_right_rounded, size: 16)]),
        ]),
      ])),
    ));
  }

  // ── SUPPORT ───────────────────────────────────────────────
  ({String label, Color color}) _ticketPill(String s) => switch (s) {
    'resolved' => (label: 'Resolved', color: BT.lime),
    'closed'   => (label: 'Closed', color: BT.mut2),
    'in_progress' => (label: 'In review', color: BT.amber),
    _          => (label: 'Open', color: BT.sky),
  };
  Widget _supportTab() {
    final tickets = ref.watch(myTicketsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myTicketsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('HELP', style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Support', style: display(29, w: FontWeight.w500)),
          ]),
          Padding(padding: const EdgeInsets.only(top: 4), child: _bell()),
        ]),
        const SizedBox(height: 16),
        AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
          Container(width: 46, height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: BT.ink)),
          const SizedBox(width: 13),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Raise a request', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 2), Text('Tap + below · we reply fast', style: TextStyle(color: BT.mut, fontSize: 12)),
          ])),
        ])),
        const SectionLabel('Your requests'),
        tickets.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.headset_mic_outlined, tint: BT.lime, title: 'No requests', subtitle: 'Anything you raise shows here with its status.')
            : Column(children: list.map((t) => Padding(padding: const EdgeInsets.only(bottom: 11),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.description == null || t.description!.isEmpty ? t.category : t.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('#${t.number} · ${t.category}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                  ])),
                  StatusPill(_ticketPill(t.status).label, color: _ticketPill(t.status).color),
                ])))).toList()),
        ),
      ]),
    );
  }

  // ── PROFILE (inline) ──────────────────────────────────────
  Widget _profileTab() {
    final u = sb.auth.currentUser;
    final name = (u?.userMetadata?['full_name'] as String?) ?? u?.email?.split('@').first ?? 'Client';
    final email = u?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
      Text('Profile', style: display(29, w: FontWeight.w500)),
      const SizedBox(height: 18),
      AppCard(padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20), child: Column(children: [
        Container(width: 74, height: 74, alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3C3DD), Color(0xFFF2A585)])),
          child: Text(initial, style: display(26, w: FontWeight.w600, c: const Color(0xFF5A2438)))),
        const SizedBox(height: 14),
        Text(name, style: display(20, w: FontWeight.w600)),
        const SizedBox(height: 8),
        const StatusPill('Client', color: BT.pink),
        if (email.isNotEmpty) ...[const SizedBox(height: 10), Text(email, style: const TextStyle(color: BT.mut, fontSize: 12.5))],
      ])),
      const SectionLabel('Account'),
      _setRow(Icons.notifications_none_rounded, 'Notifications', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
      _setRow(Icons.person_outline_rounded, 'My details', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Account details — coming soon')))),
      const SizedBox(height: 20),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => sb.auth.signOut().then((_) { if (mounted) context.go('/login'); }),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.logout_rounded, size: 19, color: BT.coral)),
          const SizedBox(width: 15),
          const Text('Log out', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.coral)),
        ]),
      ),
    ]);
  }

  Widget _setRow(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 19, color: BT.ink)),
        const SizedBox(width: 15),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ])),
  );
}

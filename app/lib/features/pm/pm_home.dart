import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
import '../admin/project_detail.dart';
import '../admin/onboard_project.dart';

/// Project Manager shell — tabs: My Builds · Projects · Schedule · Team.
/// PM owns build planning; opens project detail with editable materials.
class PMHome extends ConsumerStatefulWidget {
  const PMHome({super.key});
  @override
  ConsumerState<PMHome> createState() => _PMHomeState();
}

class _PMHomeState extends ConsumerState<PMHome> {
  int _tab = 0;
  static const _labels = ['Home', 'Projects', 'Schedule', 'Team'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: const [
        _HomeTab(), _ProjectsTab(), _ScheduleTab(), _TeamTab(),
      ])),
      bottomNavigationBar: PillNav(
        icons: const [
          Icons.home_rounded, Icons.grid_view_rounded,
          Icons.calendar_today_rounded, Icons.people_rounded,
        ],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardProject())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 24);

Widget _pmHeader(BuildContext context, String title) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('PROJECT MANAGER',
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
        final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'P';
        return Container(width: 42, height: 42, alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFA9D9EF), Color(0xFF7FBFE0)])),
          child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : 'P',
            style: display(15, w: FontWeight.w600, c: const Color(0xFF123040))));
      }),
    ),
  ])),
]);

({String label, Color color}) _statusPill(String s) => switch (s) {
  'on_track' => (label: 'On-track', color: BT.lime),
  'at_risk'  => (label: 'At-risk', color: BT.amber),
  'delayed'  => (label: 'Delayed', color: BT.coral),
  'delivered'=> (label: 'Delivered', color: BT.mint),
  _          => (label: s, color: BT.mut2),
};

Color _progressColor(String s) => switch (s) {
  'at_risk' => BT.amber, 'delayed' => BT.coral, _ => BT.lime,
};

// ───────────────────────────────────────────────────────── HOME (My Builds)

class _HomeTab extends ConsumerWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(pmDashboardProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(pmDashboardProvider.future),
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'My Builds'),
        const SizedBox(height: 20),
        dash.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (d) {
            final projects = d.projects;
            final onTrack = projects.where((p) => p.status == 'on_track').length;
            final atRisk = projects.where((p) => p.status == 'at_risk').length;
            final delayed = projects.where((p) => p.status == 'delayed').length;
            final needsYou = projects.where((p) => p.status == 'at_risk' || p.status == 'delayed').toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ASSIGNED TO ME',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${projects.length}', style: display(50, w: FontWeight.w600)),
                    const SizedBox(width: 8),
                    const Padding(padding: EdgeInsets.only(bottom: 8),
                      child: Text('active\nbuilds', style: TextStyle(color: BT.mut, fontSize: 13, height: 1.15))),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    StatusPill('$onTrack on-track', color: BT.lime),
                    StatusPill('$atRisk at-risk', color: BT.amber),
                    StatusPill('$delayed delayed', color: BT.coral),
                  ]),
                ]),
              ),
              const SectionLabel('Needs you today'),
              if (needsYou.isEmpty)
                const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                  title: 'All clear', subtitle: 'No at-risk or delayed builds right now.')
              else
                ...needsYou.map((p) => Padding(padding: const EdgeInsets.only(bottom: 11),
                  child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p.code} · ${p.name}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text('${p.progressPct}% · tag reason & reschedule', style: const TextStyle(color: BT.mut, fontSize: 12)),
                      ])),
                      StatusPill(_statusPill(p.status).label, color: _statusPill(p.status).color),
                    ]))),
                ),
              const SectionLabel("Today's stages"),
              if (d.stages.isEmpty)
                const EmptyState(icon: Icons.timelapse_rounded, tint: BT.sky,
                  title: 'Nothing in progress', subtitle: 'Stages being worked on will show here.')
              else
                ...d.stages.map((s) => Padding(padding: const EdgeInsets.only(bottom: 11),
                  child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Row(children: [
                      Container(width: 40, height: 40, alignment: Alignment.center,
                        decoration: BoxDecoration(color: BT.amber, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.handyman_rounded, size: 19, color: Color(0xFF4A3410))),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${s.projectCode} · ${s.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      const StatusPill('In progress', color: BT.sky),
                    ]))),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────── PROJECTS

class _ProjectsTab extends ConsumerStatefulWidget {
  const _ProjectsTab();
  @override
  ConsumerState<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<_ProjectsTab> {
  String _filter = 'all';
  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(myProjectsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myProjectsProvider.future),
      child: projects.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BT.ink)),
        error: (e, _) => ListView(padding: _pad, children: [
          _pmHeader(context, 'My Projects'), const SizedBox(height: 16),
          AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
        ]),
        data: (list) {
          final filtered = _filter == 'all' ? list : list.where((p) => p.status == _filter).toList();
          return ListView(padding: _pad, children: [
            _pmHeader(context, 'My Projects'),
            const SizedBox(height: 14),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              _chip('All ${list.length}', 'all'), _chip('On-track', 'on_track'),
              _chip('At-risk', 'at_risk'), _chip('Delayed', 'delayed'),
            ])),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const EmptyState(icon: Icons.grid_view_rounded, tint: BT.sky,
                title: 'No builds assigned', subtitle: 'Projects where you are the PM will appear here.')
            else if (filtered.isEmpty)
              const EmptyState(icon: Icons.grid_view_rounded, tint: BT.sky,
                title: 'Nothing here', subtitle: 'No projects match this filter.')
            else
              ...filtered.map(_row),
          ]);
        },
      ),
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
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : BT.mut)),
      ),
    ));
  }

  Widget _row(Project p) {
    final s = _statusPill(p.status);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(projectId: p.id, initial: p, materialsEditable: true))),
      child: AppCard(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${p.code} · ${p.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
          const SizedBox(width: 8),
          StatusPill(s.label, color: s.color),
        ]),
        const SizedBox(height: 11),
        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
          value: p.progressPct.clamp(0, 100) / 100, minHeight: 7,
          backgroundColor: BT.track, valueColor: AlwaysStoppedAnimation(_progressColor(p.status)))),
        const SizedBox(height: 6),
        Text('${p.progressPct}% complete', style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ])),
    ));
  }
}

// ───────────────────────────────────────────────────────────── SCHEDULE

class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bays = ref.watch(baysProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(baysProvider.future),
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'Schedule'),
        const SectionLabel('Workshop bays'),
        bays.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load bays.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.warehouse_rounded, tint: BT.sky,
                title: 'No bays set up', subtitle: 'Workshop bays and their occupancy will show here.')
            : Column(children: list.map((b) => Padding(padding: const EdgeInsets.only(bottom: 11),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Container(width: 46, height: 46, alignment: Alignment.center,
                      decoration: BoxDecoration(color: b.busy ? BT.ink : BT.card2, borderRadius: BorderRadius.circular(14)),
                      child: Text(b.name.replaceAll(RegExp(r'[^0-9]'), '').isEmpty ? b.name[0] : b.name.replaceAll(RegExp(r'[^0-9]'), ''),
                        style: display(17, w: FontWeight.w600, c: b.busy ? BT.lime : BT.mut2))),
                    const SizedBox(width: 14),
                    Expanded(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
                    StatusPill(b.busy ? 'Busy' : 'Free', color: b.busy ? BT.amber : BT.sky),
                  ]))),
              ).toList()),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────── TEAM

class _TeamTab extends ConsumerWidget {
  const _TeamTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    final workload = ref.watch(workloadProvider).valueOrNull ?? {};
    return RefreshIndicator(
      onRefresh: () async { ref.invalidate(workloadProvider); return ref.refresh(membersProvider.future); },
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'Team'),
        const SizedBox(height: 4),
        const Text('Workload across builds', style: TextStyle(color: BT.mut, fontSize: 12.5)),
        const SizedBox(height: 16),
        members.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load team.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final team = list.where((m) => m.role != 'client' && m.role != 'admin').toList();
            if (team.isEmpty) {
              return const EmptyState(icon: Icons.people_outline_rounded, tint: BT.lav,
                title: 'No team members', subtitle: 'Workshop, design and other staff will show here.');
            }
            return Column(children: team.map((m) {
              final count = workload[m.id] ?? 0;
              final overloaded = count >= 3;
              return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                child: Row(children: [
                  Container(width: 44, height: 44, alignment: Alignment.center,
                    decoration: BoxDecoration(color: roleColor(m.role), shape: BoxShape.circle),
                    child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: m.role == 'admin' ? BT.lime : BT.ink))),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name.isEmpty ? '(no name)' : m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(m.role, style: const TextStyle(color: BT.mut, fontSize: 12)),
                  ])),
                  StatusPill(count == 0 ? 'Free' : '$count task${count == 1 ? '' : 's'}',
                    color: overloaded ? BT.coral : (count == 0 ? BT.sky : BT.lime)),
                ]),
              ));
            }).toList());
          },
        ),
      ]),
    );
  }
}

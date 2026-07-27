import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'onboard_project.dart';
import 'add_member.dart';
import 'project_detail.dart';

/// Admin shell — one Scaffold, a fixed floating PillNav, and an IndexedStack
/// body so tapping the nav swaps the *content* in place (no new sheet slides in).
///  0 Home · 1 Projects · 2 Team · 3 Insights
class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  int _tab = 0;
  static const _labels = ['Home', 'Projects', 'Team', 'Insights'];

  void _fabAction() {
    // Team tab → add member; every other tab → onboard a project.
    final page = _tab == 2 ? const AddMember() : const OnboardProject();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: const [_HomeTab(), _ProjectsTab(), _TeamTab(), _InsightsTab()],
        ),
      ),
      bottomNavigationBar: PillNav(
        icons: const [
          Icons.home_rounded,
          Icons.grid_view_rounded,
          Icons.people_rounded,
          Icons.bar_chart_rounded,
        ],
        active: _tab,
        activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: _fabAction,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── shared helpers

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 24);

({String label, Color color}) _statusPill(String status) => switch (status) {
  'on_track' => (label: 'On-track', color: BT.lime),
  'at_risk'  => (label: 'At-risk', color: BT.amber),
  'delayed'  => (label: 'Delayed', color: BT.coral),
  _          => (label: status, color: BT.mut2),
};

Color _progressColor(String status) => switch (status) {
  'at_risk' => BT.amber,
  'delayed' => BT.coral,
  _         => BT.lime,
};

// ─────────────────────────────────────────────────────────────────── HOME

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    final urgentCount = fleet.valueOrNull?.urgent.length ?? 0;
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(fleetProvider.future),
      child: ListView(
        padding: _pad,
        children: [
          // ── header: title + bell + avatar
          Row(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OWNER · ADMIN',
                style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Fleet Monitor', style: display(29, w: FontWeight.w500)),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                _bell(context, urgentCount),
                const SizedBox(width: 10),
                _avatar(context),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          fleet.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not load fleet.\n$e',
              style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: _homeContent,
          ),
        ],
      ),
    );
  }

  // ── header pieces ─────────────────────────────────────────────
  Widget _bell(BuildContext context, int count) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(backgroundColor: BT.ink, content: Text('Notifications coming soon'))),
    child: Stack(clipBehavior: Clip.none, children: [
      Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
        child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
      if (count > 0) Positioned(top: -3, right: -3, child: Container(
        width: 19, height: 19, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.coral, shape: BoxShape.circle, border: Border.all(color: BT.bg, width: 2)),
        child: Text('$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF3A1C10))))),
    ]),
  );

  Widget _avatar(BuildContext context) {
    final u = sb.auth.currentUser;
    final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? 'A';
    final initial = nm.isNotEmpty ? nm[0].toUpperCase() : 'A';
    return GestureDetector(
      onTap: () => sb.auth.signOut().then((_) => context.go('/login')),
      child: Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFCFB6EF), Color(0xFFA9D9EF)])),
        child: Text(initial, style: display(15, w: FontWeight.w600, c: const Color(0xFF2A2438)))),
    );
  }

  // ── body ──────────────────────────────────────────────────────
  Widget _homeContent(FleetData f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('BUILD STATUS · THIS WEEK',
              style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
            Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: const BoxDecoration(color: BT.card2, shape: BoxShape.circle),
              child: const Icon(Icons.code_rounded, size: 15, color: BT.mut)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${f.total}', style: display(52, w: FontWeight.w600)),
            const SizedBox(width: 8),
            const Padding(padding: EdgeInsets.only(bottom: 9),
              child: Text('Active\nbuilds', style: TextStyle(color: BT.mut, fontSize: 14, height: 1.15))),
          ]),
          const SizedBox(height: 8),
          _statusTrack('On-track', f.onTrack, f.total, BT.lime, _Tex.hatch),
          _statusTrack('At-risk', f.atRisk, f.total, BT.sky, _Tex.dots),
          _statusTrack('Delayed', f.delayed, f.total, BT.coral, _Tex.plain),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${d.projectCode} · ${d.itemName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                const SizedBox(width: 8),
                StatusPill(
                  d.daysLeft <= 0 ? 'Order today' : '${d.daysLeft}d left',
                  color: d.daysLeft <= 0 ? BT.coral : BT.amber),
              ]),
              const SizedBox(height: 4),
              Text('Order-by ${d.orderByDate?.toString().split(' ').first ?? '—'} · qty ${d.qty}',
                style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            ]),
          ),
        )),
    ],
  );

  /// A candy status track: full-width textured bar + a floating % pill.
  Widget _statusTrack(String label, int count, int total, Color pill, _Tex tex) {
    final frac = total == 0 ? 0.0 : count / total;
    final pct = (frac * 100).round();
    final band = (0.34 + frac.clamp(0.0, 1.0) * 0.55).clamp(0.34, 0.93);
    final ax = band * 2 - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 44,
          child: Stack(children: [
            Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(color: BT.track, borderRadius: BorderRadius.circular(999)))),
            if (tex != _Tex.plain)
              Positioned.fill(child: CustomPaint(
                painter: tex == _Tex.hatch ? _HatchPainter() : _DotsPainter())),
            Positioned.fill(child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Align(alignment: Alignment.centerLeft,
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))))),
            Positioned.fill(child: Align(alignment: Alignment(ax.toDouble(), 0), child: _pill(pct, pill))),
          ]),
        ),
      ),
    );
  }

  Widget _pill(int pct, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999),
      boxShadow: const [BoxShadow(color: Color(0x1A695228), blurRadius: 8, offset: Offset(0, 3))]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle)),
      const SizedBox(width: 7),
      Text('$pct%', style: display(13, w: FontWeight.w600)),
    ]),
  );
}

enum _Tex { hatch, dots, plain }

class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFDED9C8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const gap = 9.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFD4CFBE);
    const gap = 11.0;
    for (double y = 7; y < size.height; y += gap) {
      for (double x = 7; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.4, p);
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ───────────────────────────────────────────────────────────────── PROJECTS

class _ProjectsTab extends ConsumerStatefulWidget {
  const _ProjectsTab();
  @override
  ConsumerState<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<_ProjectsTab> {
  String _filter = 'all'; // all | on_track | at_risk | delayed

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(fleetProvider.future),
      child: fleet.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BT.ink)),
        error: (e, _) => ListView(padding: _pad, children: [
          AppCard(child: Text('Could not load projects.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
        ]),
        data: (f) {
          final list = _filter == 'all'
              ? f.projects
              : f.projects.where((p) => p.status == _filter).toList();
          return ListView(
            padding: _pad,
            children: [
              Text('Projects', style: display(29, w: FontWeight.w500)),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('All ${f.total}', 'all'),
                  _chip('On-track', 'on_track'),
                  _chip('At-risk', 'at_risk'),
                  _chip('Delayed', 'delayed'),
                ]),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                const AppCard(child: Text('No projects in this filter.',
                  style: TextStyle(color: BT.mut, fontSize: 13)))
              else
                ...list.map(_projectRow),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value) {
    final on = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: on ? BT.ink : BT.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? BT.ink : BT.line),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
            color: on ? Colors.white : BT.mut)),
        ),
      ),
    );
  }

  Widget _projectRow(Project p) {
    final s = _statusPill(p.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(projectId: p.id, initial: p))),
        child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${p.code} · ${p.name}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
            const SizedBox(width: 8),
            StatusPill(s.label, color: s.color),
          ]),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (p.progressPct.clamp(0, 100)) / 100,
              minHeight: 7,
              backgroundColor: BT.track,
              valueColor: AlwaysStoppedAnimation(_progressColor(p.status)),
            ),
          ),
          const SizedBox(height: 6),
          Text('${p.progressPct}% complete',
            style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────── TEAM

class _TeamTab extends ConsumerWidget {
  const _TeamTab();

  static const _roleLabel = {
    'admin': 'Admin', 'pm': 'PM', 'procurement': 'Procure', 'workshop': 'Workshop',
    'store': 'Store', 'design': 'Design', 'service': 'Service', 'client': 'Client',
  };
  static const _roleDesc = {
    'admin': 'Owner · Admin', 'pm': 'Project Manager', 'procurement': 'Procurement',
    'workshop': 'Workshop Lead', 'store': 'Store / Inventory', 'design': 'Design',
    'service': 'Service', 'client': 'Client',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(membersProvider.future),
      child: members.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BT.ink)),
        error: (e, _) => ListView(padding: _pad, children: [
          AppCard(child: Text('Could not load team.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
        ]),
        data: (list) {
          final roles = list.map((m) => m.role).toSet().length;
          return ListView(
            padding: _pad,
            children: [
              Text('Team', style: display(29, w: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('${list.length} members · $roles roles',
                style: const TextStyle(color: BT.mut, fontSize: 12.5)),
              const SizedBox(height: 18),
              if (list.isEmpty)
                const AppCard(child: Text('No members yet. Tap + to add one.',
                  style: TextStyle(color: BT.mut, fontSize: 13)))
              else
                ...list.map(_memberRow),
            ],
          );
        },
      ),
    );
  }

  Widget _memberRow(Member m) {
    final rc = roleColor(m.role);
    final isAdmin = m.role == 'admin';
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: BT.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BT.line),
          boxShadow: const [BoxShadow(color: Color(0x0D695228), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: rc, shape: BoxShape.circle),
            child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16,
                color: isAdmin ? BT.lime : BT.ink)),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name.isEmpty ? '(no name)' : m.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(_roleDesc[m.role] ?? m.email,
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const SizedBox(width: 8),
          StatusPill(_roleLabel[m.role] ?? m.role, color: rc, dark: isAdmin),
        ]),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────── INSIGHTS

class _InsightsTab extends ConsumerWidget {
  const _InsightsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(fleetProvider.future),
      child: fleet.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BT.ink)),
        error: (e, _) => ListView(padding: _pad, children: [
          AppCard(child: Text('Could not load insights.\n$e',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
        ]),
        data: (f) {
          final onTime = f.total == 0 ? 0 : (f.onTrack / f.total * 100).round();
          return ListView(
            padding: _pad,
            children: [
              Text('Analytics', style: display(29, w: FontWeight.w500)),
              const SizedBox(height: 18),
              const Text('ON-TRACK DELIVERY',
                style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$onTime', style: display(48, w: FontWeight.w500)),
                Text('%', style: display(24, w: FontWeight.w500, c: BT.mut)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _statCard('${f.onTrack}', 'On-track', const Color(0xFF3D8A2F)),
                const SizedBox(width: 10),
                _statCard('${f.atRisk}', 'At-risk', const Color(0xFFC78A1F)),
                const SizedBox(width: 10),
                _statCard('${f.delayed}', 'Delayed', const Color(0xFFC65F3F)),
              ]),
              const SectionLabel('Fleet distribution'),
              _distBar('On-track', f.onTrack, f.total, BT.lime),
              _distBar('At-risk', f.atRisk, f.total, BT.amber),
              _distBar('Delayed', f.delayed, f.total, BT.coral),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String value, String label, Color color) => Expanded(
    child: AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Text(value, style: display(26, w: FontWeight.w600, c: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: BT.mut, fontSize: 11.5)),
      ]),
    ),
  );

  Widget _distBar(String label, int count, int total, Color color) {
    final frac = total == 0 ? 0.0 : count / total;
    final pct = (frac * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Stack(alignment: Alignment.centerLeft, children: [
        Container(
          height: 44,
          decoration: BoxDecoration(color: BT.track, borderRadius: BorderRadius.circular(999)),
        ),
        FractionallySizedBox(
          widthFactor: frac.clamp(0.001, 1.0).toDouble(),
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('$pct%', style: display(14, w: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

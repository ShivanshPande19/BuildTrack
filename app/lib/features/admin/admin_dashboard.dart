import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/animations.dart';
import 'onboard_project.dart';
import 'add_member.dart';
import 'project_detail.dart';
import 'company_settings.dart';
import 'ops_center.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
import '../procurement/po_approvals.dart';

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
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: TabSwitcher(
          index: _tab,
          child: const <Widget>[_HomeTab(), _ProjectsTab(), _TeamTab(), _InsightsTab()][_tab],
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

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 100); // bottom clears the floating nav (extendBody)

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
          _commandCenterCard(context),
          const SizedBox(height: 4),
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
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen())),
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Container(width: 42, height: 42, alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFCFB6EF), Color(0xFFA9D9EF)])),
        child: Text(initial, style: display(15, w: FontWeight.w600, c: const Color(0xFF2A2438)))),
    );
  }

  // ── the owner's command center entry ──────────────────────────
  Widget _commandCenterCard(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OpsCenterScreen())),
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        color: BT.ink,
        borderRadius: BorderRadius.circular(BT.radiusCard),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 14))],
      ),
      child: Row(children: [
        Container(width: 46, height: 46, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.hub_rounded, size: 24, color: BT.ink)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('COMMAND CENTER',
              style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Color(0xFF918B7C), fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 3),
          Text('The whole floor, live', style: display(19, w: FontWeight.w600, c: Colors.white)),
          const SizedBox(height: 2),
          const Text('Who\'s on what · which stage · what needs you',
            style: TextStyle(color: Color(0xFFB4AE9E), fontSize: 12)),
        ])),
        const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
      ]),
    ),
  );

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
            CountUp(f.total, style: display(52, w: FontWeight.w600)),
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
      // Purchase orders waiting for the owner's final sign-off — a late
      // signature here is a common way an order (and a build) slips.
      Consumer(builder: (context, ref, __) {
        final n = ref.watch(poApprovalsProvider).valueOrNull?.where((a) => a.awaitingFinal).length ?? 0;
        return Padding(padding: const EdgeInsets.only(top: 16), child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PoApprovalsScreen())),
          child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.request_quote_rounded, size: 20, color: BT.ink)),
            const SizedBox(width: 12),
            const Expanded(child: Text('PO approvals', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
            StatusPill(n == 0 ? 'None' : '$n to approve', color: n == 0 ? BT.mut2 : BT.sky),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
          ])),
        ));
      }),
      const SectionLabel('Needs attention'),
      if (f.urgent.isEmpty)
        const EmptyState(
          icon: Icons.check_circle_outline_rounded, tint: BT.lime,
          title: 'All caught up',
          subtitle: 'Every order-by date is on track — nothing needs attention.')
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
            Positioned.fill(child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -1.0, end: ax.toDouble()),
              duration: Motion.slow, curve: Curves.easeOutCubic,
              builder: (_, a, child) => Align(alignment: Alignment(a, 0), child: child),
              child: _pill(pct, pill))),
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
      CountUp(pct, format: (v) => '${v.round()}%', style: display(13, w: FontWeight.w600)),
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
          final noPm = f.projects.where((p) => !p.hasPm).toList();
          final list = switch (_filter) {
            'all'   => f.projects,
            'no_pm' => noPm,
            _       => f.projects.where((p) => p.status == _filter).toList(),
          };
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
                  // Builds with no PM are stranded — nobody can assign or approve
                  // their work — so they get their own filter.
                  if (noPm.isNotEmpty) _chip('No PM ${noPm.length}', 'no_pm', tint: BT.coral),
                ]),
              ),
              const SizedBox(height: 14),
              if (noPm.isNotEmpty && _filter != 'no_pm') ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _filter = 'no_pm'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
                      borderRadius: BorderRadius.circular(BT.radiusCard)),
                    child: Row(children: [
                      const Icon(Icons.person_off_rounded, size: 18, color: BT.coral),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        '${noPm.length} build${noPm.length == 1 ? '' : 's'} '
                        '${noPm.length == 1 ? 'has' : 'have'} no project manager — '
                        'their stages cannot be assigned yet.',
                        style: const TextStyle(fontSize: 12.5, height: 1.35))),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: BT.coral),
                    ]),
                  ),
                ),
              ],
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.grid_view_rounded, tint: BT.sky,
                  title: 'Nothing here',
                  subtitle: 'No projects match this filter.')
              else
                ...list.map(_projectRow),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value, {Color? tint}) {
    final on = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: on ? BT.ink : (tint ?? BT.card),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? BT.ink : (tint ?? BT.line)),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
            color: on ? Colors.white : (tint != null ? BT.ink : BT.mut))),
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
        // canAssignPm: assigning / changing the project manager is Admin's job.
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(projectId: p.id, initial: p, canAssignPm: true))),
        child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${p.code} · ${p.name}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
            const SizedBox(width: 8),
            if (!p.hasPm) ...[
              const StatusPill('No PM', color: BT.coral),
              const SizedBox(width: 6),
            ],
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

class _TeamTab extends ConsumerStatefulWidget {
  const _TeamTab();
  @override
  ConsumerState<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<_TeamTab> {
  // Active department filter. null = "All" (every department shown, grouped).
  String? _dept;

  // Departments (the broad `role`), rendered in this order. Any role not listed
  // here still shows — it's appended after the known ones.
  static const _deptOrder = [
    'admin', 'pm', 'design', 'procurement', 'workshop', 'store', 'service', 'client',
  ];
  static const _deptName = {
    'admin': 'Admin / Owner', 'pm': 'Project Managers', 'design': 'Design',
    'procurement': 'Procurement', 'workshop': 'Workshop', 'store': 'Store',
    'service': 'Service', 'client': 'Clients',
  };
  // Short labels for the filter pills (the section headers use the full names).
  static const _deptShort = {
    'admin': 'Admin', 'pm': 'PM', 'design': 'Design', 'procurement': 'Procurement',
    'workshop': 'Workshop', 'store': 'Store', 'service': 'Service', 'client': 'Clients',
  };
  static const _deptIcon = {
    'admin': Icons.shield_outlined, 'pm': Icons.engineering_outlined,
    'design': Icons.draw_outlined, 'procurement': Icons.shopping_cart_outlined,
    'workshop': Icons.build_outlined, 'store': Icons.inventory_2_outlined,
    'service': Icons.support_agent_outlined, 'client': Icons.person_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
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
          // Group members by department, then order the departments sensibly.
          final byDept = <String, List<Member>>{};
          for (final m in list) { (byDept[m.role] ??= []).add(m); }
          final depts = [
            ..._deptOrder.where(byDept.containsKey),
            ...byDept.keys.where((r) => !_deptOrder.contains(r)),
          ];
          // If the filter points at a department that no longer has members
          // (its last person was removed), quietly fall back to "All".
          final active = (_dept != null && byDept.containsKey(_dept)) ? _dept : null;
          final shown = active == null ? depts : [active];

          final children = <Widget>[
            Text('Team', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('${list.length} members · ${depts.length} departments',
              style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 18),
            _companyCard(context),
          ];

          if (list.isEmpty) {
            children.add(const EmptyState(
              icon: Icons.people_outline_rounded, tint: BT.lav,
              title: 'No members yet',
              subtitle: 'Tap + to invite your first team member.'));
          } else {
            children.add(_deptFilter(depts, byDept, active));
            children.add(const SizedBox(height: 16));
            for (final role in shown) {
              final ms = byDept[role]!
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              children.add(_deptHeader(role, ms.length));
              children.addAll(ms.map((m) => _memberRow(context, ref, m)));
            }
          }

          return ListView(padding: _pad, children: children);
        },
      ),
    );
  }

  // Horizontal filter row: an "All" pill + one pill per department (icon +
  // short name + count). Keeps the list readable once a department has many
  // people — tap a pill to see just that department.
  Widget _deptFilter(List<String> depts, Map<String, List<Member>> byDept, String? active) {
    Widget pill({
      required bool on, required IconData icon, required String label,
      required int count, required Color fill, required Color onFg, required VoidCallback onTap,
    }) {
      final fg = on ? onFg : BT.mut;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 13, 9),
          decoration: BoxDecoration(
            color: on ? fill : BT.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? Colors.transparent : BT.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
              color: on ? onFg.withValues(alpha: 0.75) : BT.mut2)),
          ]),
        ),
      );
    }

    final total = byDept.values.fold<int>(0, (s, l) => s + l.length);
    return SizedBox(
      height: 38,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        pill(
          on: active == null, icon: Icons.groups_rounded, label: 'All', count: total,
          fill: BT.ink, onFg: BT.lime,
          onTap: () => setState(() => _dept = null)),
        for (final r in depts)
          pill(
            on: active == r, icon: _deptIcon[r] ?? Icons.groups_outlined,
            label: _deptShort[r] ?? _deptName[r] ?? r, count: byDept[r]!.length,
            fill: roleColor(r), onFg: r == 'admin' ? BT.lime : BT.ink,
            onTap: () => setState(() => _dept = r)),
      ]),
    );
  }

  // One-time company identity (buyer block + GST state on every PO).
  Widget _companyCard(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CompanySettingsScreen())),
    child: Padding(padding: const EdgeInsets.only(bottom: 20),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.business_rounded, size: 20, color: BT.ink)),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Company details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          SizedBox(height: 2),
          Text('Buyer identity on every purchase order', style: TextStyle(color: BT.mut, fontSize: 12)),
        ])),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ])),
    ),
  );

  // Section header for a department: coloured icon + name + member count.
  Widget _deptHeader(String role, int count) {
    final rc = roleColor(role);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10, left: 2),
      child: Row(children: [
        Container(width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(color: rc, borderRadius: BorderRadius.circular(8)),
          child: Icon(_deptIcon[role] ?? Icons.groups_outlined, size: 15,
            color: role == 'admin' ? BT.lime : BT.ink)),
        const SizedBox(width: 10),
        Text((_deptName[role] ?? role).toUpperCase(),
          style: const TextStyle(fontSize: 11.5, letterSpacing: 1.1,
            fontWeight: FontWeight.w700, color: BT.ink)),
        const SizedBox(width: 8),
        Text('$count', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: BT.mut2)),
      ]),
    );
  }

  Widget _memberRow(BuildContext context, WidgetRef ref, Member m) {
    final rc = roleColor(m.role);
    final isAdmin = m.role == 'admin';
    final isSelf = sb.auth.currentUser?.id == m.id;
    // Within a department, the sub-team (Welding / Paint …) is the useful detail;
    // fall back to the email when the department has no sub-teams.
    final subtitle = m.subTeamName ?? m.email;

    final card = Container(
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
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 12)),
        ])),
        // Show the sub-team as a pill when the member belongs to one.
        if (m.subTeamName != null) ...[
          const SizedBox(width: 8),
          StatusPill(m.subTeamName!, color: rc, dark: isAdmin),
        ],
      ]),
    );

    // Admin can't remove themselves; everyone else is swipe-to-delete.
    if (isSelf) return Padding(padding: const EdgeInsets.only(bottom: 11), child: card);

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Dismissible(
        key: ValueKey(m.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_outline_rounded, color: BT.coral),
        ),
        confirmDismiss: (_) async {
          final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
            backgroundColor: BT.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text('Remove member?', style: display(18, w: FontWeight.w600)),
            content: Text('${m.name.isEmpty ? m.email : m.name} will lose access immediately. This cannot be undone.',
              style: const TextStyle(fontSize: 13.5, color: BT.mut)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel', style: TextStyle(color: BT.mut))),
              TextButton(onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Remove', style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700))),
            ],
          ));
          if (ok != true) return false;
          try {
            await ref.read(adminRepoProvider).deleteMember(m.id);
            ref.invalidate(membersProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: BT.ink, content: Text('${m.name.isEmpty ? m.email : m.name} removed')));
            }
            return true;
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: BT.coral, content: Text('Could not remove: $e')));
            }
            return false;
          }
        },
        child: card,
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
                CountUp(onTime, style: display(48, w: FontWeight.w500)),
                Text('%', style: display(24, w: FontWeight.w500, c: BT.mut)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _statCard(f.onTrack, 'On-track', const Color(0xFF3D8A2F)),
                const SizedBox(width: 10),
                _statCard(f.atRisk, 'At-risk', const Color(0xFFC78A1F)),
                const SizedBox(width: 10),
                _statCard(f.delayed, 'Delayed', const Color(0xFFC65F3F)),
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

  Widget _statCard(int value, String label, Color color) => Expanded(
    child: AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        CountUp(value, style: display(26, w: FontWeight.w600, c: color)),
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
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: frac.clamp(0.001, 1.0).toDouble()),
          duration: Motion.slow, curve: Curves.easeOutCubic,
          builder: (_, w, __) => FractionallySizedBox(
            widthFactor: w,
            child: Container(
              height: 44,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            CountUp(pct, format: (v) => '${v.round()}%', style: display(14, w: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

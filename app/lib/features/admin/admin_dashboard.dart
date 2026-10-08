import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/animations.dart';
import '../../shared/role_header.dart';
import 'onboard_project.dart';
import 'add_member.dart';
import 'build_screen.dart';
import 'company_settings.dart';
import 'ops_center.dart';
import '../procurement/po_approvals.dart';

/// Admin shell: one Scaffold, a fixed floating PillNav, and a [TabSwitcher]
/// body, so tapping the nav cross-fades the *content* in place (no new sheet
/// slides in). Tabs: 0 Home · 1 Projects · 2 Team · 3 Insights.
class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  int _tab = 0;
  static const _labels = ['Home', 'Projects', 'Team', 'Insights'];

  void _fabAction() {
    // The FAB is always Admin's primary create — Onboard project. Adding a
    // member is an explicit button on the Team tab; a FAB that changed identity
    // per tab was easy to misfire. (UX navigation audit, finding G.)
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardProject()));
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

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 110); // bottom clears the floating nav (extendBody)
final _dayFmt = DateFormat('d MMM');

({String label, Color color}) _statusPill(String status) => switch (status) {
  'on_track'  => (label: 'On-track', color: BT.lime),
  'at_risk'   => (label: 'At-risk', color: BT.amber),
  'delayed'   => (label: 'Delayed', color: BT.coral),
  'delivered' => (label: 'Delivered', color: BT.mint),
  _           => (label: status, color: BT.mut2),
};

Color _progressColor(String status) => switch (status) {
  'at_risk'   => BT.amber,
  'delayed'   => BT.coral,
  'delivered' => BT.mint,
  _           => BT.lime,
};

/// A small lime dot that breathes, marking the Command Center as live.
class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(width: 14, height: 14, child: AnimatedBuilder(
    animation: _c,
    builder: (_, __) {
      final t = Curves.easeOut.transform(_c.value);
      return Stack(alignment: Alignment.center, children: [
        Container(width: 6 + 8 * t, height: 6 + 8 * t,
          decoration: BoxDecoration(color: BT.lime.withValues(alpha: 0.45 * (1 - t)), shape: BoxShape.circle)),
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)),
      ]);
    }));
}

/// Shimmer placeholder in the shape of the Home tab (status card + rows).
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) => Shimmer(child: Column(children: [
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(BT.radiusCard),
        border: Border.all(color: BT.line)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SkeletonBox(width: 150, height: 11),
        SizedBox(height: 16),
        SkeletonBox(width: 90, height: 44, radius: 12),
        SizedBox(height: 16),
        SkeletonBox(height: 44, radius: 22),
        SizedBox(height: 11),
        SkeletonBox(height: 44, radius: 22),
        SizedBox(height: 11),
        SkeletonBox(height: 44, radius: 22),
      ]),
    ),
    const SizedBox(height: 16),
    const SkeletonCard(height: 68),
    const SkeletonCard(height: 68, leading: false),
  ]));
}

// ─────────────────────────────────────────────────────────────────── HOME

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(poApprovalsProvider);
        ref.invalidate(notificationsProvider);
        return ref.refresh(fleetProvider.future);
      },
      child: ListView(
        padding: _pad,
        children: [
          // The bell badge counts UNREAD notifications (RoleHeader reads them),
          // not urgent order-by items, which have their own section below.
          const FadeSlideIn(child: RoleHeader(role: 'admin', eyebrow: 'Owner · Admin', title: 'Fleet Monitor')),
          const SizedBox(height: 20),
          FadeSlideIn(delay: Motion.stagger(1), child: _commandCenterCard(context)),
          const SizedBox(height: 16),
          fleet.when(
            skipLoadingOnRefresh: true,
            loading: () => const _HomeSkeleton(),
            error: (e, _) => ErrorCard('Could not load fleet.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(fleetProvider)),
            data: (f) => _homeContent(context, f),
          ),
        ],
      ),
    );
  }

  // ── the owner's command center entry ──────────────────────────
  Widget _commandCenterCard(BuildContext context) => PressableScale(
    pressedScale: 0.98,
    haptic: true,
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
          const Row(children: [
            Text('COMMAND CENTER',
              style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Color(0xFF918B7C), fontWeight: FontWeight.w700)),
            SizedBox(width: 8),
            _LiveDot(),
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
  Widget _homeContent(BuildContext context, FleetData f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: staggered([
      AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BUILD STATUS · RIGHT NOW',
            style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          // "Active" means not yet delivered. It used to count delivered builds
          // too, so the three shares below never added up to 100%.
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CountUp(f.active, style: display(52, w: FontWeight.w600)),
            const SizedBox(width: 8),
            const Padding(padding: EdgeInsets.only(bottom: 9),
              child: Text('Active\nbuilds', style: TextStyle(color: BT.mut, fontSize: 14, height: 1.15))),
            const Spacer(),
            if (f.delivered > 0)
              Padding(padding: const EdgeInsets.only(bottom: 12),
                child: StatusPill('${f.delivered} delivered', color: BT.mint)),
          ]),
          const SizedBox(height: 8),
          // At-risk is amber everywhere else in the app; it was sky here.
          _statusTrack('On-track', f.onTrack, f.active, BT.lime, _Tex.hatch),
          _statusTrack('At-risk', f.atRisk, f.active, BT.amber, _Tex.dots),
          _statusTrack('Delayed', f.delayed, f.active, BT.coral, _Tex.plain),
        ]),
      ),
      // Purchase orders waiting for the owner's final sign-off. A late
      // signature here is a common way an order (and a build) slips.
      Consumer(builder: (context, ref, __) {
        final n = ref.watch(poApprovalsProvider).valueOrNull?.where((a) => a.awaitingFinal).length ?? 0;
        return Padding(padding: const EdgeInsets.only(top: 16), child: AppCard(
          onTap: () async {
            // Capture the container: this Consumer can be gone by the time the
            // pushed screen returns, and a disposed `ref` throws.
            final c = ProviderScope.containerOf(context, listen: false);
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PoApprovalsScreen()));
            c.invalidate(poApprovalsProvider);
          },
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.request_quote_rounded, size: 20, color: BT.ink)),
            const SizedBox(width: 12),
            const Expanded(child: Text('PO approvals', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
            AnimatedSwap(child: StatusPill(n == 0 ? 'None' : '$n to approve',
              key: ValueKey(n), color: n == 0 ? BT.mut2 : BT.sky)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
          ])));
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
              Text('Order by ${d.orderByDate == null ? '—' : _dayFmt.format(d.orderByDate!)} · qty ${d.qty}',
                style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            ]),
          ),
        )),
    ], stepMs: 55),
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
  String _filter = 'all'; // all | on_track | at_risk | delayed | delivered | no_pm

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(fleetProvider.future),
      child: ListView(
        padding: _pad,
        children: [
          FadeSlideIn(child: Text('Projects', style: display(29, w: FontWeight.w500))),
          const SizedBox(height: 14),
          ...fleet.when(
            skipLoadingOnRefresh: true,
            loading: () => const [SkeletonList(count: 5, leading: false)],
            error: (e, _) => [ErrorCard('Could not load projects.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(fleetProvider))],
            data: _content,
          ),
        ],
      ),
    );
  }

  List<Widget> _content(FleetData f) {
    final noPm = f.projects.where((p) => !p.hasPm).toList();
    final delivered = f.projects.where((p) => p.status == 'delivered').length;
    // If a filter's last build moved away (e.g. its PM was assigned), fall back.
    if (_filter == 'no_pm' && noPm.isEmpty) _filter = 'all';
    if (_filter == 'delivered' && delivered == 0) _filter = 'all';
    final list = switch (_filter) {
      'all'   => f.projects,
      'no_pm' => noPm,
      _       => f.projects.where((p) => p.status == _filter).toList(),
    };
    return [
      FadeSlideIn(delay: Motion.stagger(1), child: ChipBar(chips: [
        _chip('All', 'all', count: f.total),
        _chip('On-track', 'on_track', count: f.onTrack),
        _chip('At-risk', 'at_risk', count: f.atRisk),
        _chip('Delayed', 'delayed', count: f.delayed),
        if (delivered > 0) _chip('Delivered', 'delivered', count: delivered),
        // Builds with no PM are stranded (nobody can assign or approve their
        // work), so they get their own filter.
        if (noPm.isNotEmpty) _chip('No PM', 'no_pm', count: noPm.length, tint: BT.coral),
      ])),
      const SizedBox(height: 14),
      AnimatedSize(
        duration: Motion.base, curve: Motion.move, alignment: Alignment.topCenter,
        child: (noPm.isNotEmpty && _filter != 'no_pm') ? _noPmBanner(noPm.length) : const SizedBox(width: double.infinity),
      ),
      // Re-key the list on filter change so it cross-fades and cascades in,
      // instead of rows popping in and out.
      AnimatedSwitcher(
        duration: Motion.base,
        switchInCurve: Motion.curve,
        switchOutCurve: Motion.exit,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, if (cur != null) cur]),
        child: KeyedSubtree(
          key: ValueKey(_filter),
          child: list.isEmpty
            ? const EmptyState(
                icon: Icons.grid_view_rounded, tint: BT.sky,
                title: 'Nothing here',
                subtitle: 'No projects match this filter.')
            : Column(children: staggered(list.map(_projectRow).toList())),
        ),
      ),
    ];
  }

  Widget _noPmBanner(int n) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: PressableScale(
      pressedScale: 0.98,
      haptic: true,
      onTap: () => setState(() => _filter = 'no_pm'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
          borderRadius: BorderRadius.circular(BT.radiusCard)),
        child: Row(children: [
          const Icon(Icons.person_off_rounded, size: 18, color: BT.coral),
          const SizedBox(width: 10),
          Expanded(child: Text(
            '$n build${n == 1 ? '' : 's'} ${n == 1 ? 'has' : 'have'} no project manager. '
            '${n == 1 ? 'Its' : 'Their'} stages cannot be assigned yet.',
            style: const TextStyle(fontSize: 12.5, height: 1.35))),
          const Icon(Icons.chevron_right_rounded, size: 18, color: BT.coral),
        ]),
      ),
    ),
  );

  Widget _chip(String label, String value, {int? count, Color? tint}) => AppChip(
    label,
    selected: _filter == value,
    count: count,
    tint: tint,
    onTap: () => setState(() => _filter = value),
  );

  Widget _projectRow(Project p) {
    final s = _statusPill(p.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: AppCard(
        // canAssignPm: assigning / changing the project manager is Admin's job.
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BuildScreen(projectId: p.id, initial: p, canAssignPm: true)));
          // A PM may have been assigned or a document added inside.
          ref.invalidate(fleetProvider);
        },
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
          const SizedBox(height: 12),
          AnimatedBar(fraction: p.progressPct.clamp(0, 100) / 100, color: _progressColor(p.status), height: 7),
          const SizedBox(height: 7),
          Row(children: [
            CountUp(p.progressPct, format: (v) => '${v.round()}% complete',
              style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.arrow_forward_rounded, size: 16, color: BT.mut2),
          ]),
        ]),
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

  // Members removed in this session. Hidden immediately so a swiped-away row
  // never flashes back while membersProvider refetches.
  final Set<String> _removed = {};

  Future<void> _addMember() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddMember()));
    // AddMember already invalidates membersProvider on success; this also
    // covers the case where the admin backs out.
    if (mounted) ref.invalidate(membersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    final count = members.valueOrNull?.where((m) => !_removed.contains(m.id)).length;
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(membersProvider.future),
      child: ListView(padding: _pad, children: [
        // ── Header: the primary action sits beside the title, where it belongs.
        // It used to be a full-width ink bar wedged under "Company details",
        // with uneven gaps around it.
        FadeSlideIn(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Team', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 2),
            AnimatedSwap(child: Text(
              count == null ? 'Loading members…' : '$count member${count == 1 ? '' : 's'}',
              key: ValueKey(count),
              style: const TextStyle(color: BT.mut, fontSize: 12.5))),
          ])),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(bottom: 2),
            child: PillAction('Add member', icon: Icons.person_add_alt_1_rounded, onTap: _addMember)),
        ])),
        const SizedBox(height: 18),
        ...members.when(
          skipLoadingOnRefresh: true,
          loading: () => const [SkeletonList(count: 6)],
          error: (e, _) => [ErrorCard('Could not load team.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(membersProvider))],
          data: (all) => _content(context, all.where((m) => !_removed.contains(m.id)).toList()),
        ),
      ]),
    );
  }

  List<Widget> _content(BuildContext context, List<Member> list) {
    // Group members by department, then order the departments sensibly.
    final byDept = <String, List<Member>>{};
    for (final m in list) { (byDept[m.role] ??= []).add(m); }
    final depts = [
      ..._deptOrder.where(byDept.containsKey),
      ...byDept.keys.where((r) => !_deptOrder.contains(r)),
    ];
    // If the filter points at a department that no longer has members (its
    // last person was removed), quietly fall back to "All".
    final active = (_dept != null && byDept.containsKey(_dept)) ? _dept : null;
    final shown = active == null ? depts : [active];

    final rows = <Widget>[];
    for (final role in shown) {
      final ms = [...byDept[role]!]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      rows.add(_deptHeader(role, ms.length));
      rows.addAll(ms.map((m) => _memberRow(context, m)));
    }

    return [
      if (list.isEmpty)
        const EmptyState(
          icon: Icons.people_outline_rounded, tint: BT.lav,
          title: 'No members yet',
          subtitle: 'Tap "Add member" to create the first login and pick its role.')
      else ...[
        FadeSlideIn(delay: Motion.stagger(1), child: _deptFilter(depts, byDept, active)),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.curve,
          switchOutCurve: Motion.exit,
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, if (cur != null) cur]),
          child: Column(key: ValueKey(active), crossAxisAlignment: CrossAxisAlignment.start,
            children: staggered(rows, stepMs: 30, maxMs: 300)),
        ),
      ],
      // ── Workspace settings live in their own section, away from people.
      const SectionLabel('Workspace'),
      FadeSlideIn(delay: Motion.stagger(3), child: _companyCard(context)),
    ];
  }

  // Horizontal filter row: an "All" chip + one chip per department (icon +
  // short name + count). Keeps the list readable once a department has many
  // people. Tap a chip to see just that department.
  Widget _deptFilter(List<String> depts, Map<String, List<Member>> byDept, String? active) {
    final total = byDept.values.fold<int>(0, (s, l) => s + l.length);
    return ChipBar(chips: [
      AppChip('All', selected: active == null, icon: Icons.groups_rounded, count: total,
        onTap: () => setState(() => _dept = null)),
      for (final r in depts)
        AppChip(_deptShort[r] ?? _deptName[r] ?? r,
          selected: active == r,
          icon: _deptIcon[r] ?? Icons.groups_outlined,
          count: byDept[r]!.length,
          selectedColor: roleColor(r),
          selectedFg: r == 'admin' ? BT.lime : BT.ink,
          onTap: () => setState(() => _dept = r)),
    ]);
  }

  // One-time company identity (buyer block + GST state on every PO).
  Widget _companyCard(BuildContext context) => AppCard(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CompanySettingsScreen())),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(width: 40, height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.business_rounded, size: 20, color: BT.ink)),
      const SizedBox(width: 12),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Company details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        SizedBox(height: 2),
        Text('Buyer name, GSTIN and state on every purchase order', style: TextStyle(color: BT.mut, fontSize: 12)),
      ])),
      const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
    ]),
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

  Widget _memberRow(BuildContext context, Member m) {
    final rc = roleColor(m.role);
    final isAdmin = m.role == 'admin';
    final isSelf = sb.auth.currentUser?.id == m.id;
    // The sub-team (Welding / Paint …) is shown once, as a pill. The line
    // under the name is always the email (it used to repeat the sub-team).
    final note = switch (m.status) {
      'invited'  => (label: 'Invited', color: BT.amber),
      'disabled' => (label: 'Disabled', color: BT.mut2),
      _          => null,
    };

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
          Row(children: [
            Flexible(child: Text(m.name.isEmpty ? '(no name)' : m.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
            if (isSelf) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(8)),
                child: const Text('You', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: BT.mut))),
            ],
          ]),
          const SizedBox(height: 2),
          Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 12)),
        ])),
        if (note != null) ...[
          const SizedBox(width: 8),
          StatusPill(note.label, color: note.color),
        ] else if (m.subTeamName != null) ...[
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
        onDismissed: (_) => setState(() => _removed.add(m.id)),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_outline_rounded, color: BT.coral),
        ),
        confirmDismiss: (_) async {
          Haptic.confirm();
          final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
            title: const Text('Remove member?'),
            content: Text('${m.name.isEmpty ? m.email : m.name} will lose access immediately. This cannot be undone.'),
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
                backgroundColor: BT.coral, content: Text('Could not remove: ${friendlyError(e)}')));
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
      child: ListView(padding: _pad, children: [
        FadeSlideIn(child: Text('Insights', style: display(29, w: FontWeight.w500))),
        const SizedBox(height: 18),
        ...fleet.when(
          skipLoadingOnRefresh: true,
          loading: () => const [SkeletonList(count: 4, leading: false)],
          error: (e, _) => [ErrorCard('Could not load insights.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(fleetProvider))],
          data: (f) {
            // Share of ACTIVE builds that are on track. Delivered builds are
            // finished. They used to sit in the denominator, so the % fell
            // every time a truck was handed over.
            final active = f.active;
            final onTime = active == 0 ? 0 : (f.onTrack / active * 100).round();
            return staggered([
              const Text('ON-TRACK · ACTIVE BUILDS',
                style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                CountUp(onTime, style: display(48, w: FontWeight.w500)),
                Text('%', style: display(24, w: FontWeight.w500, c: BT.mut)),
                const Spacer(),
                Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: Text('$active active · ${f.delivered} delivered',
                    style: const TextStyle(color: BT.mut, fontSize: 12))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _statCard(f.onTrack, 'On-track', const Color(0xFF3D8A2F)),
                const SizedBox(width: 10),
                _statCard(f.atRisk, 'At-risk', const Color(0xFFC78A1F)),
                const SizedBox(width: 10),
                _statCard(f.delayed, 'Delayed', const Color(0xFFC65F3F)),
              ]),
              const SectionLabel('Active fleet distribution'),
              _distBar('On-track', f.onTrack, active, BT.lime),
              _distBar('At-risk', f.atRisk, active, BT.amber),
              _distBar('Delayed', f.delayed, active, BT.coral),
            ], stepMs: 50);
          },
        ),
      ]),
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
        // 0% shows an empty track. It used to draw a hairline sliver (clamp 0.001).
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: frac.clamp(0.0, 1.0).toDouble()),
          duration: Motion.slow, curve: Curves.easeOutCubic,
          builder: (_, w, __) => w <= 0 ? const SizedBox.shrink() : FractionallySizedBox(
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

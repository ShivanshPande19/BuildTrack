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
import '../admin/build_screen.dart';
import '../procurement/po_approvals.dart';
import 'approvals.dart';
import 'assign_work.dart';

/// Project Manager shell. Tabs: Home (My Builds) · Projects · Schedule · Team.
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
      extendBody: true,
      body: SafeArea(bottom: false, child: TabSwitcher(index: _tab, child: const <Widget>[
        _HomeTab(), _ProjectsTab(), _ScheduleTab(), _TeamTab(),
      ][_tab])),
      bottomNavigationBar: PillNav(
        icons: const [
          Icons.home_rounded, Icons.grid_view_rounded,
          Icons.calendar_today_rounded, Icons.people_rounded,
        ],
        active: _tab,
        activeLabel: _labels[_tab],
        actionIcon: Icons.person_add_alt_1_rounded,
        onTap: (i) => setState(() => _tab = i),
        // A PM's key action is handing work out, not creating builds — onboarding
        // a project (and creating client logins) is Admin-only, and the database
        // now enforces that too.
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AssignWorkScreen())),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 8, 20, 110); // bottom clears the floating nav (extendBody)

Widget _pmHeader(BuildContext context, String title) =>
    FadeSlideIn(child: RoleHeader(role: 'pm', eyebrow: 'Project manager', title: title));

/// Opens a build with the PM's full controls, then refreshes everything a PM
/// change inside could have touched.
Future<void> _openBuild(BuildContext context, WidgetRef ref, {required String projectId, Project? initial}) async {
  // Capture the container up front: the row that called this may be rebuilt
  // away while the build is open, and a disposed `ref` throws.
  final c = ProviderScope.containerOf(context, listen: false);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BuildScreen(projectId: projectId, initial: initial,
      materialsEditable: true, canAssign: true, canEditTimeline: true)));
  c.invalidate(pmDashboardProvider);
  c.invalidate(myProjectsProvider);
  c.invalidate(pmScheduleProvider);
  c.invalidate(stagesToAssignProvider);
  c.invalidate(buildsNeedingPlanProvider);
}

/// Which build to set up, when more than one is waiting for a plan.
Future<Project?> _pickUnplanned(BuildContext context, List<Project> list) =>
  showAppSheet<Project>(context: context, builder: (sctx) => Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Builds with no plan', style: display(20, w: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('Choose the workflow each one follows. Until it has one, none of '
                 'its work can be assigned.',
        style: TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
      const SizedBox(height: 14),
      Flexible(child: ListView(shrinkWrap: true, children: [
        for (final p in list)
          Padding(padding: const EdgeInsets.only(bottom: 9), child: AppCard(
            onTap: () => Navigator.pop(sctx, p),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(child: Text('${p.code} · ${p.name}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
              const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
            ]))),
      ])),
    ]));

/// A "needs you" shortcut card: icon tile, title, live count pill, chevron.
Widget _shortcut(BuildContext context, {required IconData icon, required Color tint, required String title,
    required Widget pill, required Future<void> Function() onTap}) => Padding(
  padding: const EdgeInsets.only(bottom: 11),
  child: AppCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(width: 40, height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: BT.ink)),
      const SizedBox(width: 12),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
      AnimatedSwap(child: pill),
      const SizedBox(width: 6),
      const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
    ]),
  ),
);

({String label, Color color}) _statusPill(String s) => switch (s) {
  'on_track' => (label: 'On-track', color: BT.lime),
  'at_risk'  => (label: 'At-risk', color: BT.amber),
  'delayed'  => (label: 'Delayed', color: BT.coral),
  'delivered'=> (label: 'Delivered', color: BT.mint),
  _          => (label: s, color: BT.mut2),
};

Color _progressColor(String s) => switch (s) {
  'at_risk' => BT.amber, 'delayed' => BT.coral, 'delivered' => BT.mint, _ => BT.lime,
};

// ───────────────────────────────────────────────────────── HOME (My Builds)

class _HomeTab extends ConsumerWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(pmDashboardProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(stagesToAssignProvider);
        ref.invalidate(buildsNeedingPlanProvider);
        ref.invalidate(pendingApprovalsProvider);
        ref.invalidate(poApprovalsProvider);
        return ref.refresh(pmDashboardProvider.future);
      },
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'My Builds'),
        const SizedBox(height: 20),
        dash.when(
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => ErrorCard('Could not load.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(pmDashboardProvider)),
          data: (d) {
            final projects = d.projects;
            final onTrack = projects.where((p) => p.status == 'on_track').length;
            final atRisk = projects.where((p) => p.status == 'at_risk').length;
            final delayed = projects.where((p) => p.status == 'delayed').length;
            final delivered = projects.where((p) => p.status == 'delivered').length;
            // "Active" should not count trucks that have already gone out.
            final active = projects.length - delivered;
            final needsYou = projects.where((p) => p.status == 'at_risk' || p.status == 'delayed').toList();
            final byId = {for (final p in projects) p.id: p};
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ASSIGNED TO ME',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    CountUp(active, style: display(50, w: FontWeight.w600)),
                    const SizedBox(width: 8),
                    const Padding(padding: EdgeInsets.only(bottom: 8),
                      child: Text('active\nbuilds', style: TextStyle(color: BT.mut, fontSize: 13, height: 1.15))),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    StatusPill('$onTrack on-track', color: BT.lime),
                    StatusPill('$atRisk at-risk', color: BT.amber),
                    StatusPill('$delayed delayed', color: BT.coral),
                    if (delivered > 0) StatusPill('$delivered delivered', color: BT.mint),
                  ]),
                ]),
              ),
              const SectionLabel('Needs you today'),
              // A build handed over with no plan (0031) has no stages, so it
              // added nothing to Assign work — which then said "All done" while
              // nothing on that build could start. It leads: until it has a
              // plan, nothing else about it can happen.
              Consumer(builder: (_, r, __) {
                final unplanned = r.watch(buildsNeedingPlanProvider).valueOrNull ?? const <Project>[];
                if (unplanned.isEmpty) return const SizedBox.shrink();
                final n = unplanned.length;
                return _shortcut(context, icon: Icons.playlist_add_rounded, tint: BT.amber, title: 'Set up a plan',
                  pill: StatusPill('$n build${n == 1 ? '' : 's'}', key: ValueKey(n), color: BT.amber),
                  onTap: () async {
                    final p = n == 1 ? unplanned.first : await _pickUnplanned(context, unplanned);
                    if (p == null || !context.mounted) return;
                    await _openBuild(context, ref, projectId: p.id, initial: p);
                  });
              }),
              // Unassigned work blocks the whole build, so it sits above approvals.
              Consumer(builder: (_, r, __) {
                final n = r.watch(stagesToAssignProvider).valueOrNull?.length ?? 0;
                // "All done" is only true of builds that have a plan to be done with.
                final unplanned = r.watch(buildsNeedingPlanProvider).valueOrNull?.isNotEmpty ?? false;
                final label = n > 0 ? '$n waiting' : unplanned ? 'Nothing yet' : 'All done';
                return _shortcut(context, icon: Icons.person_add_alt_1_rounded, tint: BT.lav, title: 'Assign work',
                  pill: StatusPill(label, key: ValueKey(label), color: n == 0 ? BT.mut2 : BT.lav),
                  onTap: () async {
                    // This Consumer can be disposed while the pushed screen is
                    // open (e.g. a background refresh fails), so grab the
                    // container first; a disposed `ref` throws.
                    final c = ProviderScope.containerOf(context, listen: false);
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssignWorkScreen()));
                    c.invalidate(stagesToAssignProvider);
                  });
              }),
              Consumer(builder: (_, r, __) {
                final n = r.watch(pendingApprovalsProvider).valueOrNull?.length ?? 0;
                return _shortcut(context, icon: Icons.verified_rounded, tint: BT.lime, title: 'Approvals',
                  pill: StatusPill(n == 0 ? 'None' : '$n pending', key: ValueKey(n), color: n == 0 ? BT.mut2 : BT.amber),
                  onTap: () async {
                    // This Consumer can be disposed while the pushed screen is
                    // open (e.g. a background refresh fails), so grab the
                    // container first; a disposed `ref` throws.
                    final c = ProviderScope.containerOf(context, listen: false);
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApprovalsScreen()));
                    c.invalidate(pendingApprovalsProvider);
                  });
              }),
              // Purchase orders on my builds waiting for my signature.
              Consumer(builder: (_, r, __) {
                final uid = sb.auth.currentUser?.id;
                final n = r.watch(poApprovalsProvider).valueOrNull
                    ?.where((a) => a.awaitingPm && a.pmId == uid).length ?? 0;
                return _shortcut(context, icon: Icons.request_quote_rounded, tint: BT.sky, title: 'PO approvals',
                  pill: StatusPill(n == 0 ? 'None' : '$n to sign', key: ValueKey(n), color: n == 0 ? BT.mut2 : BT.sky),
                  onTap: () async {
                    // This Consumer can be disposed while the pushed screen is
                    // open (e.g. a background refresh fails), so grab the
                    // container first; a disposed `ref` throws.
                    final c = ProviderScope.containerOf(context, listen: false);
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PoApprovalsScreen()));
                    c.invalidate(poApprovalsProvider);
                  });
              }),
              // The three shortcuts above are actions; these are problems. They
              // used to run on under the same heading with nothing separating
              // them, so the list changed meaning halfway with no warning. Its
              // own heading says what it is — and carries the count, capped,
              // because a PM holding a dozen slipping builds needs the worst
              // few on the home screen, not all twelve.
              CappedSection(
                label: 'At risk or delayed',
                sheetTitle: 'At risk or delayed',
                max: 4,
                items: [
                  // These rows promised "tag reason & reschedule" but did nothing
                  // on tap. They now open the build, where Log a delay and the
                  // delivery date live.
                  for (final p in needsYou)
                    Padding(padding: const EdgeInsets.only(bottom: 11),
                      child: AppCard(
                        onTap: () => _openBuild(context, ref, projectId: p.id, initial: p),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p.code} · ${p.name}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text('${p.progressPct}% · tap to log the delay or reschedule',
                              style: const TextStyle(color: BT.mut, fontSize: 12)),
                          ])),
                          StatusPill(_statusPill(p.status).label, color: _statusPill(p.status).color),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                        ]))),
                ],
                empty: const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                  title: 'All clear',
                  subtitle: 'None of your builds are at risk or delayed right now.'),
              ),
              CappedSection(
                label: "Today's stages",
                sheetTitle: 'In progress today',
                max: 5,
                items: [
                  for (final s in d.stages)
                    Padding(padding: const EdgeInsets.only(bottom: 11),
                      child: AppCard(
                        onTap: s.projectId.isEmpty ? null
                          : () => _openBuild(context, ref, projectId: s.projectId, initial: byId[s.projectId]),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(children: [
                          Container(width: 40, height: 40, alignment: Alignment.center,
                            decoration: BoxDecoration(color: BT.amber, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.handyman_rounded, size: 19, color: Color(0xFF4A3410))),
                          const SizedBox(width: 12),
                          Expanded(child: Text('${s.projectCode} · ${s.name}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                          const StatusPill('In progress', color: BT.sky),
                        ]))),
                ],
                empty: const EmptyState(icon: Icons.timelapse_rounded, tint: BT.sky,
                  title: 'Nothing in progress', subtitle: 'Stages being worked on will show here.'),
              ),
            ], stepMs: 45));
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
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'My Projects'),
        const SizedBox(height: 14),
        ...projects.when(
          skipLoadingOnRefresh: true,
          loading: () => const [SkeletonList(count: 5, leading: false)],
          error: (e, _) => [ErrorCard('Could not load.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(myProjectsProvider))],
          data: (list) {
            int n(String s) => list.where((p) => p.status == s).length;
            final delivered = n('delivered');
            if (_filter == 'delivered' && delivered == 0) _filter = 'all';
            final filtered = _filter == 'all' ? list : list.where((p) => p.status == _filter).toList();
            return [
              FadeSlideIn(delay: Motion.stagger(1), child: ChipBar(chips: [
                _chip('All', 'all', list.length),
                _chip('On-track', 'on_track', n('on_track')),
                _chip('At-risk', 'at_risk', n('at_risk')),
                _chip('Delayed', 'delayed', n('delayed')),
                if (delivered > 0) _chip('Delivered', 'delivered', delivered),
              ])),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: Motion.base,
                switchInCurve: Motion.curve,
                switchOutCurve: Motion.exit,
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, if (cur != null) cur]),
                child: KeyedSubtree(key: ValueKey(_filter), child: list.isEmpty
                  ? const EmptyState(icon: Icons.grid_view_rounded, tint: BT.sky,
                      title: 'No builds assigned', subtitle: 'Projects where you are the PM will appear here.')
                  : filtered.isEmpty
                    ? const EmptyState(icon: Icons.grid_view_rounded, tint: BT.sky,
                        title: 'Nothing here', subtitle: 'No projects match this filter.')
                    : Column(children: staggered(filtered.map(_row).toList()))),
              ),
            ];
          },
        ),
      ]),
    );
  }

  Widget _chip(String label, String value, int count) => AppChip(label,
    selected: _filter == value, count: count, onTap: () => setState(() => _filter = value));

  Widget _row(Project p) {
    final s = _statusPill(p.status);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
      onTap: () => _openBuild(context, ref, projectId: p.id, initial: p),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${p.code} · ${p.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
          const SizedBox(width: 8),
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
    ));
  }
}

// ───────────────────────────────────────────────────────────── SCHEDULE

/// PM Schedule (p5) — what is due, and what has already slipped.
///
/// This used to be a workshop bay board reading the `bays` table. Nothing ever
/// wrote to it, so it could only show "No bays set up". Bays are gone; the tab
/// now answers the question a PM actually opens it for, off the stage dates that
/// assignment and backward scheduling already produce.
/// The PM's Schedule, in two lenses.
///
/// **Builds** (the default) keeps each build whole: one card per build, worst
/// first, carrying its whole pipeline as a strip and a line saying what is
/// holding it up. **Dates** is the old view — a flat list of open stages
/// grouped by when they are due — which is still the right answer to "what is
/// due this week", and the wrong one to "which truck is in trouble".
///
/// The flat view was the only one, and it does not survive scale: ten builds of
/// seven stages interleave into seventy rows and the build, which is the thing
/// a PM manages, stops being visible at all.
class _ScheduleTab extends ConsumerStatefulWidget {
  const _ScheduleTab();
  @override
  ConsumerState<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<_ScheduleTab> {
  int _lens = 0;            // 0 = by build, 1 = by date
  String _cut = 'all';      // builds lens filter

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pmBuildScheduleProvider);
        return ref.refresh(pmScheduleProvider.future);
      },
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'Schedule'),
        const SizedBox(height: 4),
        FadeSlideIn(child: Text(
          _lens == 0 ? 'Every build you own, worst first' : 'Open stages across your builds',
          style: const TextStyle(color: BT.mut, fontSize: 12.5))),
        const SizedBox(height: 14),
        FadeSlideIn(delay: Motion.stagger(1), child: SegmentTabs(
          labels: const ['Builds', 'Dates'],
          index: _lens,
          onChanged: (i) => setState(() => _lens = i),
          padding: EdgeInsets.zero,
        )),
        const SizedBox(height: 16),
        if (_lens == 0) _byBuild(context) else _byDate(context),
      ]),
    );
  }

  // ── lens 1: build by build ───────────────────────────────────────────────
  Widget _byBuild(BuildContext context) {
    final builds = ref.watch(pmBuildScheduleProvider);
    return builds.when(
      skipLoadingOnRefresh: true,
      loading: () => const SkeletonList(count: 4),
      error: (e, _) => ErrorCard('Could not load your builds.\n${friendlyError(e)}',
        onRetry: () => ref.invalidate(pmBuildScheduleProvider)),
      data: (list) {
        final live = list.where((b) => !b.isDelivered).toList();
        if (live.isEmpty) {
          return const EmptyState(icon: Icons.calendar_today_rounded, tint: BT.sky,
            title: 'Nothing scheduled',
            subtitle: 'Builds you manage show up here with their whole pipeline.');
        }
        final onYou = live.where((b) => b.awaitingCount > 0).toList();
        final action = live.where((b) => !b.isClear).toList();
        final clear = live.where((b) => b.isClear).toList();

        // A PM holding thirty builds needs to narrow, not scroll. Capping is
        // the wrong tool on a dedicated screen — you came here to see them —
        // so this filters, the way PM Projects and the Command Center do.
        // A cut whose builds have all cleared quietly falls back to All, so
        // you are never left staring at an empty list you cannot explain.
        final cuts = {'all': live, 'on_you': onYou, 'action': action, 'clear': clear};
        if ((cuts[_cut] ?? const <BuildSchedule>[]).isEmpty) _cut = 'all';
        final shown = cuts[_cut]!;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
          _lensSummary(live, action.length),
          const SizedBox(height: 16),
          ChipBar(chips: [
            AppChip('All', selected: _cut == 'all', count: live.length,
              icon: Icons.grid_view_rounded, onTap: () => setState(() => _cut = 'all')),
            if (onYou.isNotEmpty)
              AppChip('Waiting on you', selected: _cut == 'on_you', count: onYou.length,
                icon: Icons.hourglass_top_rounded, selectedColor: BT.amber,
                onTap: () => setState(() => _cut = 'on_you')),
            if (action.isNotEmpty)
              AppChip('Need action', selected: _cut == 'action', count: action.length,
                icon: Icons.priority_high_rounded, selectedColor: BT.coral,
                onTap: () => setState(() => _cut = 'action')),
            if (clear.isNotEmpty)
              AppChip('On track', selected: _cut == 'clear', count: clear.length,
                icon: Icons.check_circle_outline_rounded, selectedColor: BT.lime,
                onTap: () => setState(() => _cut = 'clear')),
          ]),
          const SizedBox(height: 16),
          // Keyed on the cut so the list cross-fades rather than snapping.
          AnimatedSwitcher(
            duration: Motion.base,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.exit,
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            layoutBuilder: (cur, prev) =>
              Stack(alignment: Alignment.topCenter, children: [...prev, if (cur != null) cur]),
            child: Column(key: ValueKey(_cut), crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final b in shown) _buildCard(context, b)]),
          ),
        ], stepMs: 40));
      },
    );
  }

  /// Three numbers about the *fleet* the PM holds, not about stages.
  Widget _lensSummary(List<BuildSchedule> live, int needsYou) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
    child: Row(children: [
      Expanded(child: _stat('${live.length}', 'Builds', BT.ink)),
      Container(width: 1, height: 34, color: BT.line),
      Expanded(child: _stat('${live.where((b) => b.awaitingCount > 0).length}',
        'Waiting on you', live.any((b) => b.awaitingCount > 0) ? BT.amber : BT.mut2)),
      Container(width: 1, height: 34, color: BT.line),
      Expanded(child: _stat('$needsYou', 'Need action', needsYou > 0 ? BT.coral : BT.mut2)),
    ]),
  );

  Widget _buildCard(BuildContext context, BuildSchedule b) {
    final sp = _statusPill(b.project.status);
    final d = b.daysToDelivery;
    final deliveryLate = d != null && d < 0;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: AppCard(
      onTap: () => _openBuild(context, ref, projectId: b.project.id, initial: b.project),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${b.project.code} · ${b.project.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          const SizedBox(width: 8),
          StatusPill(sp.label, color: sp.color),
        ]),
        const SizedBox(height: 12),
        PipelineStrip(stages: b.stages),
        const SizedBox(height: 11),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.current == null
                ? 'No stages yet'
                : 'Stage ${b.currentIndex} of ${b.total} · ${b.current!.name}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 3),
            Text(
              [
                b.blockedLabel,
                if (b.current?.assigneeName != null) b.current!.assigneeName!,
              ].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12,
                color: b.isClear ? BT.mut : BT.coral,
                fontWeight: b.isClear ? FontWeight.w500 : FontWeight.w600)),
          ])),
          const SizedBox(width: 10),
          if (b.targetDelivery != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmt.format(b.targetDelivery!),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                deliveryLate ? '${-d}d late' : (d == 0 ? 'today' : 'in ${d}d'),
                style: TextStyle(fontSize: 11,
                  color: deliveryLate ? BT.coral : BT.mut, fontWeight: FontWeight.w600)),
            ]),
        ]),
      ]),
    ));
  }

  // ── lens 2: the old flat list, grouped by due date ───────────────────────
  Widget _byDate(BuildContext context) {
    final schedule = ref.watch(pmScheduleProvider);
    return schedule.when(
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(count: 6),
          error: (e, _) => ErrorCard('Could not load your schedule.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(pmScheduleProvider)),
          data: (all) {
            if (all.isEmpty) {
              return const EmptyState(icon: Icons.calendar_today_rounded, tint: BT.sky,
                title: 'Nothing scheduled',
                subtitle: 'Once you have builds with open stages, they show up here by due date.');
            }

            final overdue  = all.where((e) => e.isOverdue).toList();
            final today    = all.where((e) => e.isDueToday).toList();
            final soon     = all.where((e) {
              final d = e.daysLeft;
              return d != null && d > 0 && d <= 7;
            }).toList();
            final later    = all.where((e) {
              final d = e.daysLeft;
              return d != null && d > 7;
            }).toList();
            final undated  = all.where((e) => e.hasNoDate).toList();

            // Overdue and Due today are shown whole: they are the ones a PM
            // has to act on, and hiding any of them behind a tap would be the
            // screen failing at its one job. The further out a group is, the
            // longer and the less urgent it gets — across ten builds "Later"
            // alone can run to forty rows — so those cap.
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
              _summary(overdue.length, today.length + soon.length, undated.length),
              if (overdue.isNotEmpty) ...[
                const SectionLabel('Overdue'),
                ...overdue.map((e) => _row(context, e)),
              ],
              if (today.isNotEmpty) ...[
                const SectionLabel('Due today'),
                ...today.map((e) => _row(context, e)),
              ],
              CappedSection(
                label: 'Next 7 days', sheetTitle: 'Due in the next 7 days', max: 6,
                items: [for (final e in soon) _row(context, e)]),
              CappedSection(
                label: 'Later', sheetTitle: 'Due later', max: 4,
                items: [for (final e in later) _row(context, e)]),
              CappedSection(
                label: 'No date yet', sheetTitle: 'Stages with no date', max: 4,
                items: [for (final e in undated) _row(context, e)]),
            ], stepMs: 35));
          },
        );
  }

  /// Three numbers a PM can act on, rather than a decorative header.
  Widget _summary(int overdue, int dueThisWeek, int undated) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
    child: Row(children: [
      Expanded(child: _stat('$overdue', 'Overdue', overdue > 0 ? BT.coral : BT.mut2)),
      Container(width: 1, height: 34, color: BT.line),
      Expanded(child: _stat('$dueThisWeek', 'This week', dueThisWeek > 0 ? BT.ink : BT.mut2)),
      Container(width: 1, height: 34, color: BT.line),
      Expanded(child: _stat('$undated', 'No date', undated > 0 ? BT.amber : BT.mut2)),
    ]),
  );

  Widget _stat(String value, String label, Color color) => Column(children: [
    CountUp(int.tryParse(value) ?? 0, style: display(26, w: FontWeight.w600, c: color)),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
  ]);

  Widget _row(BuildContext context, ScheduleEntry e) {
    final tint = e.isOverdue ? BT.coral : (e.isDueToday ? BT.amber : (e.hasNoDate ? BT.card2 : BT.sky));
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
      // Straight into the build so the PM can reassign or move the date. Pass
      // the code and name so the header doesn't fall back to "BUILD / Build".
      onTap: () => _openBuild(context, ref, projectId: e.projectId,
        initial: Project(id: e.projectId, code: e.projectCode, name: e.projectName,
          status: 'on_track', progressPct: 0)),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13),
              border: e.hasNoDate ? Border.all(color: BT.line) : null),
            child: Icon(
              e.isOverdue ? Icons.priority_high_rounded
                : (e.hasNoDate ? Icons.event_busy_rounded : Icons.event_rounded),
              size: 20, color: e.hasNoDate ? BT.mut2 : BT.ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.projectCode} · ${e.stageName}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 3),
            Text(_subtitle(e), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const SizedBox(width: 8),
          StatusPill(_dueLabel(e), color: tint == BT.card2 ? BT.mut2 : tint),
        ])),
    );
  }

  /// Who holds it, plus the date itself — an unassigned stage is called out,
  /// because that is the PM's problem to fix and nobody else's.
  String _subtitle(ScheduleEntry e) {
    final who = e.isUnassigned
      ? 'Unassigned${e.discipline == null ? '' : ' · ${e.discipline}'}'
      : (e.assigneeName?.isNotEmpty == true ? e.assigneeName! : 'Assigned');
    if (e.due == null) return '$who · no due date set';
    final when = _fmt.format(e.due!);
    return '$who · ${e.dueIsPlanned ? 'planned' : 'due'} $when';
  }

  String _dueLabel(ScheduleEntry e) {
    final d = e.daysLeft;
    if (d == null) return 'No date';
    if (d < 0) return '${-d}d late';
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    return 'in ${d}d';
  }
}

// ───────────────────────────────────────────────────────────── TEAM

class _TeamTab extends ConsumerWidget {
  const _TeamTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    final workload = ref.watch(workloadProvider).valueOrNull ?? {};
    // The PM's own stages, so tapping a member can show *which* work they hold.
    // Already loaded for the Schedule tab, so this costs nothing extra.
    //
    // `hasValue` matters: landing on Team first leaves this still in flight,
    // and an empty list would make the sheet announce "busy elsewhere" about
    // someone whose stages simply had not arrived yet.
    final scheduleAsync = ref.watch(pmScheduleProvider);
    final mine = scheduleAsync.valueOrNull ?? const <ScheduleEntry>[];
    final scheduleReady = scheduleAsync.hasValue;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(workloadProvider);
        ref.invalidate(pmScheduleProvider);
        return ref.refresh(membersProvider.future);
      },
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'Team'),
        const SizedBox(height: 4),
        const FadeSlideIn(child: Text('Open stages per person, across all builds', style: TextStyle(color: BT.mut, fontSize: 12.5))),
        const SizedBox(height: 16),
        members.when(
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(count: 6),
          error: (e, _) => ErrorCard('Could not load team.\n${friendlyError(e)}',
            onRetry: () => ref.invalidate(membersProvider)),
          data: (list) {
            // PM's team = execution staff they assign build tasks to (not admins/PMs/clients/procurement).
            const doerRoles = {'workshop', 'design', 'store', 'service'};
            // Disabled accounts can't be assigned work, so they don't belong here.
            final team = list.where((m) => doerRoles.contains(m.role) && m.status != 'disabled').toList()
              ..sort((a, b) => (workload[b.id] ?? 0).compareTo(workload[a.id] ?? 0));
            if (team.isEmpty) {
              return const EmptyState(icon: Icons.people_outline_rounded, tint: BT.lav,
                title: 'No team members', subtitle: 'Workshop, design, store & service staff will show here.');
            }
            return Column(children: staggered(team.map((m) {
              final count = workload[m.id] ?? 0;
              final overloaded = count >= 3;
              final theirs = mine.where((e) => e.assigneeId == m.id).toList();
              final late = theirs.where((e) => e.isOverdue).length;
              return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
                // "2 open" was a number you could not act on. Tapping now shows
                // which stages they are, on which builds, due when.
                onTap: () => _showMemberWork(context, ref, m, theirs, count, ready: scheduleReady),
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
                    Text([
                        m.subTeamName == null ? _roleName(m.role) : '${_roleName(m.role)} · ${m.subTeamName}',
                        if (late > 0) '$late overdue',
                      ].join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: late > 0 ? BT.coral : BT.mut,
                        fontWeight: late > 0 ? FontWeight.w600 : FontWeight.w500)),
                  ])),
                  StatusPill(count == 0 ? 'Free' : '$count open',
                    color: overloaded ? BT.coral : (count == 0 ? BT.sky : BT.lime)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                ]),
              ));
            }).toList(), stepMs: 30));
          },
        ),
      ]),
    );
  }
}

/// What one team member is actually holding, opened from the Team tab.
///
/// "2 open" was a number with nothing behind it. A PM looking at it wants the
/// next question answered — *which* two, on which builds, due when — and then
/// wants to act on one. Every row opens its build.
///
/// [total] comes from the fleet-wide workload count and [theirs] from this PM's
/// own builds, so the two can legitimately differ: a fitter can be busy on a
/// build this PM does not manage. That gap is stated rather than hidden,
/// because "free" when someone is booked solid elsewhere is the one wrong
/// answer this screen could give.
void _showMemberWork(BuildContext context, WidgetRef ref, Member m,
    List<ScheduleEntry> theirs, int total, {required bool ready}) {
  final fmt = DateFormat('d MMM');
  final elsewhere = total - theirs.length;

  showAppSheet<void>(
    context: context,
    builder: (sheetCtx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Row(children: [
            Container(width: 46, height: 46, alignment: Alignment.center,
              decoration: BoxDecoration(color: roleColor(m.role), shape: BoxShape.circle),
              child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: BT.ink))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name.isEmpty ? '(no name)' : m.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: display(19, w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(m.subTeamName == null ? _roleName(m.role) : '${_roleName(m.role)} · ${m.subTeamName}',
                style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            ])),
            StatusPill(total == 0 ? 'Free' : '$total open',
              color: total >= 3 ? BT.coral : (total == 0 ? BT.sky : BT.lime)),
          ]),
        ),

        if (!ready)
          // Still loading. Saying nothing is better than saying the wrong thing.
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: SkeletonList(count: 2, leading: true, trailingPill: true))
        else if (theirs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: EmptyState(
              icon: elsewhere > 0 ? Icons.work_history_outlined : Icons.beach_access_outlined,
              tint: elsewhere > 0 ? BT.amber : BT.sky,
              title: elsewhere > 0 ? 'Busy elsewhere' : 'Nothing assigned',
              subtitle: elsewhere > 0
                ? 'They hold $elsewhere open ${elsewhere == 1 ? 'stage' : 'stages'} on builds you do not manage.'
                : 'They have no open stages on any build. A good moment to hand them something.'),
          )
        else
          Flexible(child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              for (final e in theirs) _memberStageRow(sheetCtx, ref, e, fmt),
              if (elsewhere > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                  child: Text(
                    'Also $elsewhere open ${elsewhere == 1 ? 'stage' : 'stages'} on builds you do not manage.',
                    style: const TextStyle(color: BT.mut2, fontSize: 11.5)),
                ),
            ],
          )),

        const SizedBox(height: 14),
        PrimaryButton(ready && theirs.isEmpty ? 'Assign work' : 'Assign more work',
          icon: Icons.person_add_alt_1_rounded,
          onTap: () async {
            Navigator.pop(sheetCtx);
            final c = ProviderScope.containerOf(context, listen: false);
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AssignWorkScreen()));
            c.invalidate(workloadProvider);
            c.invalidate(pmScheduleProvider);
            c.invalidate(pmBuildScheduleProvider);
            c.invalidate(stagesToAssignProvider);
          }),
      ],
    ),
  );
}

/// One stage in the member sheet. The person is already known from the header,
/// so the row leads with the build and the stage and spends its space on the
/// date instead of repeating the name.
Widget _memberStageRow(BuildContext sheetCtx, WidgetRef ref, ScheduleEntry e, DateFormat fmt) {
  final d = e.daysLeft;
  final tint = e.isOverdue ? BT.coral : (e.isDueToday ? BT.amber : (e.hasNoDate ? BT.card2 : BT.sky));
  final label = d == null
      ? 'No date'
      : (d < 0 ? '${-d}d late' : (d == 0 ? 'Today' : (d == 1 ? 'Tomorrow' : 'in ${d}d')));

  return Padding(padding: const EdgeInsets.only(bottom: 10), child: AppCard(
    onTap: () {
      // Close the sheet first: coming back from the build to a stale sheet
      // listing work that may no longer be theirs is worse than no sheet.
      Navigator.pop(sheetCtx);
      _openBuild(sheetCtx, ref, projectId: e.projectId,
        initial: Project(id: e.projectId, code: e.projectCode, name: e.projectName,
          status: 'on_track', progressPct: 0));
    },
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(width: 8, height: 36,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${e.projectCode} · ${e.stageName}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 3),
        Text(e.due == null
            ? 'No due date set'
            : '${e.dueIsPlanned ? 'Planned' : 'Due'} ${fmt.format(e.due!)}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: BT.mut, fontSize: 12)),
      ])),
      const SizedBox(width: 8),
      StatusPill(label, color: tint == BT.card2 ? BT.mut2 : tint),
    ]),
  ));
}

String _roleName(String r) => switch (r) {
  'workshop' => 'Workshop', 'design' => 'Design', 'store' => 'Store', 'service' => 'Service', _ => r,
};

/// A build's whole pipeline as one strip: a segment per stage, in order.
///
/// Public so `test/widgets_test.dart` can pump it directly: it is the only
/// per-stage drawing on the Schedule, so it is where a semantics or layout
/// complaint on that screen would come from.
///
/// This is the part of the Schedule that scales. A PM with ten builds scans ten
/// strips and sees instantly which ones are red and how far along each is —
/// something a flat list of seventy stage rows cannot show at any length.
///
/// The segments are flex-sized rather than fixed, so a three-stage template and
/// a twelve-stage one both fill the card edge to edge and stay comparable.
class PipelineStrip extends StatelessWidget {
  final List<StageTick> stages;
  const PipelineStrip({super.key, required this.stages});

  /// Colour by what the PM has to do about it, not by raw status: a stage
  /// waiting on the PM reads differently from one simply in progress.
  Color _tint(StageTick s) {
    if (s.awaitingApproval) return BT.amber;
    if (s.isDone) return BT.lime;
    if (s.isOverdue) return BT.coral;
    if (s.isRework) return BT.coral;
    if (s.isActive) return BT.sky;
    if (s.isUnassigned) return BT.card2;
    return BT.line;
  }

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return Container(height: 10,
        decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(5)));
    }
    final current = () {
      for (final s in stages) { if (s.isActive) return s; }
      for (final s in stages) { if (!s.isDone) return s; }
      return null;
    }();

    // One label for the whole strip, and the segments themselves excluded.
    //
    // A Semantics node per segment made a screen reader read seven of them —
    // "Design: done, Fabrication: in_progress, Paint: todo…" — which is noise,
    // not information. The summary is what a sighted user takes from the strip
    // in one glance, so it is what the strip should say.
    final done = stages.where((s) => s.isDone).length;
    return Semantics(
      label: current == null
          ? '$done of ${stages.length} stages done'
          : '$done of ${stages.length} stages done, now on ${current.name}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 14,
          child: Row(children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(child: Container(
                // The stage being worked sits taller, so "where is this build"
                // is readable without counting segments.
                height: identical(stages[i], current) ? 14 : 9,
                decoration: BoxDecoration(
                  color: _tint(stages[i]),
                  borderRadius: BorderRadius.circular(5),
                  border: stages[i].isUnassigned && !stages[i].isDone
                    ? Border.all(color: BT.line) : null,
                ),
              )),
            ],
          ]),
        ),
      ),
    );
  }
}

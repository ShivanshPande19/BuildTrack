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
}

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
              // Unassigned work blocks the whole build, so it sits above approvals.
              Consumer(builder: (_, r, __) {
                final n = r.watch(stagesToAssignProvider).valueOrNull?.length ?? 0;
                return _shortcut(context, icon: Icons.person_add_alt_1_rounded, tint: BT.lav, title: 'Assign work',
                  pill: StatusPill(n == 0 ? 'All done' : '$n waiting', key: ValueKey(n), color: n == 0 ? BT.mut2 : BT.lav),
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
              if (needsYou.isEmpty)
                const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                  title: 'All clear', subtitle: 'No at-risk or delayed builds right now.')
              else
                // These rows promised "tag reason & reschedule" but did nothing on
                // tap. They now open the build, where Log a delay and the delivery
                // date live.
                ...needsYou.map((p) => Padding(padding: const EdgeInsets.only(bottom: 11),
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
                ),
              const SectionLabel("Today's stages"),
              if (d.stages.isEmpty)
                const EmptyState(icon: Icons.timelapse_rounded, tint: BT.sky,
                  title: 'Nothing in progress', subtitle: 'Stages being worked on will show here.')
              else
                ...d.stages.map((s) => Padding(padding: const EdgeInsets.only(bottom: 11),
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
class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab();

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(pmScheduleProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(pmScheduleProvider.future),
      child: ListView(padding: _pad, children: [
        _pmHeader(context, 'Schedule'),
        const SizedBox(height: 4),
        const FadeSlideIn(child: Text('Open stages across your builds', style: TextStyle(color: BT.mut, fontSize: 12.5))),
        const SizedBox(height: 16),
        schedule.when(
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

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
              _summary(overdue.length, today.length + soon.length, undated.length),
              if (overdue.isNotEmpty) ...[
                const SectionLabel('Overdue'),
                ...overdue.map((e) => _row(context, ref, e)),
              ],
              if (today.isNotEmpty) ...[
                const SectionLabel('Due today'),
                ...today.map((e) => _row(context, ref, e)),
              ],
              if (soon.isNotEmpty) ...[
                const SectionLabel('Next 7 days'),
                ...soon.map((e) => _row(context, ref, e)),
              ],
              if (later.isNotEmpty) ...[
                const SectionLabel('Later'),
                ...later.map((e) => _row(context, ref, e)),
              ],
              if (undated.isNotEmpty) ...[
                const SectionLabel('No date yet'),
                ...undated.map((e) => _row(context, ref, e)),
              ],
            ], stepMs: 35));
          },
        ),
      ]),
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

  Widget _row(BuildContext context, WidgetRef ref, ScheduleEntry e) {
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
    return RefreshIndicator(
      onRefresh: () async { ref.invalidate(workloadProvider); return ref.refresh(membersProvider.future); },
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
                    Text(m.subTeamName == null ? _roleName(m.role) : '${_roleName(m.role)} · ${m.subTeamName}',
                      style: const TextStyle(color: BT.mut, fontSize: 12)),
                  ])),
                  StatusPill(count == 0 ? 'Free' : '$count open',
                    color: overloaded ? BT.coral : (count == 0 ? BT.sky : BT.lime)),
                ]),
              ));
            }).toList(), stepMs: 30));
          },
        ),
      ]),
    );
  }
}

String _roleName(String r) => switch (r) {
  'workshop' => 'Workshop', 'design' => 'Design', 'store' => 'Store', 'service' => 'Service', _ => r,
};

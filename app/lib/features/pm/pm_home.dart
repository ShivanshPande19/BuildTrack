import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
import '../common/profile.dart';
import '../admin/project_detail.dart';
import 'approvals.dart';
import 'assign_work.dart';

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
      onRefresh: () async {
        ref.invalidate(stagesToAssignProvider);
        ref.invalidate(pendingApprovalsProvider);
        return ref.refresh(pmDashboardProvider.future);
      },
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
            final delivered = projects.where((p) => p.status == 'delivered').length;
            // "Active" should not count trucks that have already gone out.
            final active = projects.length - delivered;
            final needsYou = projects.where((p) => p.status == 'at_risk' || p.status == 'delayed').toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ASSIGNED TO ME',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$active', style: display(50, w: FontWeight.w600)),
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
              Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AssignWorkScreen())),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                  Container(width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(color: BT.lav, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.person_add_alt_1_rounded, size: 20, color: BT.ink)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Assign work', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
                  Consumer(builder: (_, r, __) {
                    final n = r.watch(stagesToAssignProvider).valueOrNull?.length ?? 0;
                    return StatusPill(n == 0 ? 'All done' : '$n waiting',
                      color: n == 0 ? BT.mut2 : BT.lav);
                  }),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                ])),
              )),
              Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApprovalsScreen())),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                  Container(width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.verified_rounded, size: 20, color: BT.ink)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Approvals', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
                  Consumer(builder: (_, r, __) {
                    final n = r.watch(pendingApprovalsProvider).valueOrNull?.length ?? 0;
                    return StatusPill(n == 0 ? 'None' : '$n pending', color: n == 0 ? BT.mut2 : BT.amber);
                  }),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                ])),
              )),
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
        builder: (_) => ProjectDetailScreen(projectId: p.id, initial: p,
          materialsEditable: true, canAssign: true, canEditTimeline: true))),
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
        const Text('Open stages across your builds', style: TextStyle(color: BT.mut, fontSize: 12.5)),
        const SizedBox(height: 16),
        schedule.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load your schedule.\n${friendlyError(e)}',
            style: const TextStyle(color: BT.coral, fontSize: 13))),
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

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _summary(overdue.length, today.length + soon.length, undated.length),
              if (overdue.isNotEmpty) ...[
                const SectionLabel('Overdue'),
                ...overdue.map((e) => _row(context, e)),
              ],
              if (today.isNotEmpty) ...[
                const SectionLabel('Due today'),
                ...today.map((e) => _row(context, e)),
              ],
              if (soon.isNotEmpty) ...[
                const SectionLabel('Next 7 days'),
                ...soon.map((e) => _row(context, e)),
              ],
              if (later.isNotEmpty) ...[
                const SectionLabel('Later'),
                ...later.map((e) => _row(context, e)),
              ],
              if (undated.isNotEmpty) ...[
                const SectionLabel('No date yet'),
                ...undated.map((e) => _row(context, e)),
              ],
            ]);
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
    Text(value, style: display(26, w: FontWeight.w600, c: color)),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
  ]);

  Widget _row(BuildContext context, ScheduleEntry e) {
    final tint = e.isOverdue ? BT.coral : (e.isDueToday ? BT.amber : (e.hasNoDate ? BT.card2 : BT.sky));
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Straight into the build so the PM can reassign or move the date.
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(projectId: e.projectId,
          materialsEditable: true, canAssign: true, canEditTimeline: true))),
      child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
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
    ));
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
        const Text('Workload across builds', style: TextStyle(color: BT.mut, fontSize: 12.5)),
        const SizedBox(height: 16),
        members.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load team.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            // PM's team = execution staff they assign build tasks to (not admins/PMs/clients/procurement).
            const doerRoles = {'workshop', 'design', 'store', 'service'};
            final team = list.where((m) => doerRoles.contains(m.role)).toList();
            if (team.isEmpty) {
              return const EmptyState(icon: Icons.people_outline_rounded, tint: BT.lav,
                title: 'No team members', subtitle: 'Workshop, design, store & service staff will show here.');
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

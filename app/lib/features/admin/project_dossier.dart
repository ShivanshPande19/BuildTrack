import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'project_detail.dart';

/// Admin — the project dossier: a read-oriented, accountability view of one
/// build. Where it is right now and who has it, the full stage pipeline with
/// each stage's assignee and planned-vs-actual dates, and the delay ledger —
/// which stage slipped, who held it, why, and for how many days. So the owner
/// gets the whole story of a build in one screen instead of drilling stage by
/// stage.
class ProjectDossierScreen extends ConsumerWidget {
  const ProjectDossierScreen({super.key, required this.projectId, this.code});
  final String projectId;
  final String? code;

  static final _fmt = DateFormat('d MMM');
  static String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  ({String label, Color color}) _status(String s) => switch (s) {
    'on_track'  => (label: 'On-track', color: BT.lime),
    'at_risk'   => (label: 'At-risk', color: BT.amber),
    'delayed'   => (label: 'Delayed', color: BT.coral),
    'delivered' => (label: 'Delivered', color: BT.mint),
    _           => (label: s, color: BT.mut2),
  };

  ({String label, IconData icon}) _disc(String? d) => switch (d) {
    'workshop'    => (label: 'Workshop', icon: Icons.handyman_rounded),
    'design'      => (label: 'Design', icon: Icons.brush_rounded),
    'store'       => (label: 'Store', icon: Icons.inventory_2_rounded),
    'procurement' => (label: 'Procurement', icon: Icons.shopping_cart_rounded),
    'service'     => (label: 'Service', icon: Icons.build_rounded),
    _             => (label: d ?? '—', icon: Icons.category_rounded),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(projectDetailProvider(projectId));
    final delays = ref.watch(projectDelaysProvider(projectId));
    final members = {
      for (final m in (ref.watch(membersProvider).valueOrNull ?? <Member>[])) m.id: m
    };
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(projectDelaysProvider(projectId));
          return ref.refresh(projectDetailProvider(projectId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Text(code ?? 'Dossier', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            const Text('BUILD DOSSIER',
              style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            detail.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load the dossier.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (d) => _content(context, ref, d, delays.valueOrNull ?? const [], members),
            ),
          ],
        ),
      )),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, ProjectDetailData d,
      List<ProjectDelay> delays, Map<String, Member> members) {
    final sp = _status(d.project.status);
    // where it is now: the in-progress stage, else the first not-done, else last
    final current = d.stages.isEmpty ? null : d.stages.firstWhere(
      (s) => s.status == 'in_progress',
      orElse: () => d.stages.firstWhere((s) => s.status != 'done', orElse: () => d.stages.last));
    final totalDelay = delays.fold<int>(0, (a, x) => a + x.days);
    final delaysByStage = <String, List<ProjectDelay>>{};
    for (final x in delays) { (delaysByStage[x.stageId] ??= []).add(x); }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(d.project.name, style: display(27, w: FontWeight.w600))),
        const SizedBox(width: 10),
        StatusPill(sp.label, color: sp.color),
      ]),
      const SizedBox(height: 16),

      _summary(context, d, current, members, totalDelay),

      if (delays.isNotEmpty) ...[
        SectionLabel('Delays · ${delays.length} logged · $totalDelay day${totalDelay == 1 ? '' : 's'} total'),
        ...delays.map(_delayRow),
      ],

      const SectionLabel('The pipeline'),
      if (d.stages.isEmpty)
        const EmptyState(icon: Icons.timeline_rounded, tint: BT.amber,
          title: 'No stages yet', subtitle: 'Stages generate from the workflow template on onboarding.')
      else
        ...List.generate(d.stages.length, (i) => _stageTile(
          d.stages[i], i == d.stages.length - 1, members, delaysByStage[d.stages[i].id] ?? const [])),

      const SizedBox(height: 20),
      // For the admin who wants to act (assign PM, edit, deliver).
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(projectId: projectId, initial: d.project, canAssignPm: true))),
        child: Container(height: 50, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.tune_rounded, size: 18, color: BT.ink), SizedBox(width: 8),
            Text('Open build controls', style: TextStyle(fontWeight: FontWeight.w600)),
          ])),
      ),
    ]);
  }

  // ── summary: where it is, who has it, progress, delay total ──────────────
  Widget _summary(BuildContext context, ProjectDetailData d, Stage? current,
      Map<String, Member> members, int totalDelay) {
    final done = d.project.status == 'delivered';
    final assignee = current?.assigneeId == null ? null : members[current!.assigneeId];
    final who = done ? 'Delivered'
      : current == null ? '—'
      : assignee == null ? 'Unassigned'
      : '${assignee.name}${assignee.subTeamName != null ? ' · ${assignee.subTeamName}' : ''}';
    final disc = _disc(current?.discipline);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: BT.ink, borderRadius: BorderRadius.circular(BT.radiusCard),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 14))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('WHERE IT IS NOW',
          style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Color(0xFF918B7C), fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: done ? BT.mint : BT.lime, borderRadius: BorderRadius.circular(12)),
            child: Icon(done ? Icons.check_rounded : disc.icon, size: 20, color: BT.ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(done ? 'Delivered' : (current?.name ?? 'No active stage'),
              style: display(18, w: FontWeight.w600, c: Colors.white),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(done ? 'Handed over to the client' : 'With · $who',
              style: const TextStyle(color: Color(0xFFB4AE9E), fontSize: 12.5),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _sumStat('${d.project.progressPct}%', 'Progress', Colors.white),
          _sumDiv(),
          _sumStat('$totalDelay', totalDelay == 1 ? 'Delay day' : 'Delay days',
            totalDelay > 0 ? BT.coral : Colors.white),
          _sumDiv(),
          _sumStat(_d(d.targetDelivery), 'Delivery', Colors.white),
        ]),
      ]),
    );
  }

  Widget _sumStat(String v, String l, Color c) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(v, style: display(19, w: FontWeight.w600, c: c), maxLines: 1, overflow: TextOverflow.ellipsis),
    Text(l, style: const TextStyle(color: Color(0xFF918B7C), fontSize: 11, fontWeight: FontWeight.w600)),
  ]));
  Widget _sumDiv() => Container(width: 1, height: 30, color: const Color(0xFF3A3833), margin: const EdgeInsets.symmetric(horizontal: 14));

  // ── one delay in the ledger ──────────────────────────────────────────────
  Widget _delayRow(ProjectDelay x) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.coral, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.timelapse_rounded, size: 17, color: Color(0xFF5A2410))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.stageName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text('${_cap(x.reason)}${x.assigneeName != null ? ' · ${x.assigneeName}' : ''}',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: BT.coral, borderRadius: BorderRadius.circular(999)),
            child: Text('+${x.days}d', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5A2410))),
          ),
        ]),
        if (x.note != null && x.note!.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(x.note!, style: const TextStyle(fontSize: 12.5, color: BT.ink, height: 1.35, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 6),
        Text('Logged by ${x.loggedByName ?? '—'}${x.at != null ? ' · ${_d(x.at)}' : ''}',
          style: const TextStyle(fontSize: 11, color: BT.mut2, fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  // ── one stage on the pipeline (read) ─────────────────────────────────────
  Widget _stageTile(Stage s, bool isLast, Map<String, Member> members, List<ProjectDelay> stageDelays) {
    final done = s.status == 'done';
    final now = s.status == 'in_progress';
    final rework = s.status == 'rework';
    final todo = s.status == 'todo';
    final assignee = s.assigneeId == null ? null : members[s.assigneeId];
    final who = assignee == null ? 'Unassigned'
      : '${assignee.name}${assignee.subTeamName != null ? ' · ${assignee.subTeamName}' : ''}';
    final late = done && s.actualEnd != null && s.plannedEnd != null && s.actualEnd!.isAfter(s.plannedEnd!);
    final disc = _disc(s.discipline);
    final delayDays = stageDelays.fold<int>(0, (a, x) => a + x.days);

    Widget dot;
    if (done) {
      dot = Container(width: 24, height: 24, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 14, color: BT.ink));
    } else if (now) {
      dot = Container(width: 24, height: 24, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle),
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
    } else if (rework) {
      dot = Container(width: 24, height: 24, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.coral, shape: BoxShape.circle),
        child: const Icon(Icons.replay_rounded, size: 13, color: BT.ink));
    } else {
      dot = Container(width: 24, height: 24,
        decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 1.5)));
    }

    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(children: [
        dot,
        if (!isLast) Expanded(child: Container(width: 2, color: BT.line, margin: const EdgeInsets.symmetric(vertical: 2))),
      ]),
      const SizedBox(width: 14),
      Expanded(child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 1),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: BT.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: now ? BT.ink : BT.line, width: now ? 1.4 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.name, style: TextStyle(fontSize: 14.5,
                fontWeight: todo ? FontWeight.w600 : FontWeight.w700,
                color: todo ? BT.mut : BT.ink))),
              if (s.discipline != null) _discChip(disc, s.discipline!),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              const Icon(Icons.person_outline_rounded, size: 14, color: BT.mut),
              const SizedBox(width: 5),
              Expanded(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: assignee == null && !done ? BT.coral : BT.mut))),
            ]),
            const SizedBox(height: 7),
            // planned vs actual — the accountability line
            Row(children: [
              _dateChip('Planned', s.plannedStart, s.plannedEnd, BT.mut2),
              const SizedBox(width: 8),
              if (s.actualStart != null || s.actualEnd != null)
                _dateChip('Actual', s.actualStart, s.actualEnd, late ? BT.coral : BT.mut),
            ]),
            if (delayDays > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timelapse_rounded, size: 13, color: BT.coral),
                  const SizedBox(width: 5),
                  Text('Slipped $delayDays day${delayDays == 1 ? '' : 's'} · ${stageDelays.map((d) => _cap(d.reason)).toSet().join(', ')}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF7A2E14), fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ),
      )),
    ]));
  }

  Widget _discChip(({String label, IconData icon}) disc, String discipline) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: roleColor(discipline), borderRadius: BorderRadius.circular(999)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(disc.icon, size: 12, color: BT.ink),
      const SizedBox(width: 4),
      Text(disc.label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: BT.ink)),
    ]),
  );

  Widget _dateChip(String label, DateTime? start, DateTime? end, Color tint) => Flexible(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: BT.mut2)),
      Flexible(child: Text('${_d(start)} – ${_d(end)}', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tint))),
    ]),
  ));

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

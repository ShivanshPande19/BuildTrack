import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'stage_detail.dart';
import 'project_requirements.dart';

/// Admin — Project detail (a4): progress, delivery date and the build-stage timeline.
class ProjectDetailScreen extends ConsumerWidget {
  final String projectId;
  final Project? initial; // for an instant header while stages load
  final bool materialsEditable; // PM opens editable; Admin monitors (read-only)
  final bool canAssign;         // PM can assign stages to team members
  const ProjectDetailScreen({super.key, required this.projectId, this.initial,
    this.materialsEditable = false, this.canAssign = false});

  static final _fmt = DateFormat('d MMM');
  String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  ({String label, Color color}) _status(String s) => switch (s) {
    'on_track' => (label: 'On-track', color: BT.lime),
    'at_risk'  => (label: 'At-risk', color: BT.amber),
    'delayed'  => (label: 'Delayed', color: BT.coral),
    'delivered'=> (label: 'Delivered', color: BT.mint),
    _          => (label: s, color: BT.mut2),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(projectDetailProvider(projectId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(projectDetailProvider(projectId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            // top row: back + code pill
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              if (initial != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Text(initial!.code, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            detail.when(
              loading: () => _headerFromInitial(),
              error: (e, _) => AppCard(child: Text('Could not load project.\n$e',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (d) => _content(context, ref, d),
            ),
          ],
        ),
      )),
    );
  }

  Widget _headerFromInitial() => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Center(child: Column(children: [
      if (initial != null) Text(initial!.name, style: display(24, w: FontWeight.w600)),
      const SizedBox(height: 24),
      const CircularProgressIndicator(color: BT.ink),
    ])),
  );

  Widget _content(BuildContext context, WidgetRef ref, ProjectDetailData d) {
    final s = _status(d.project.status);
    final cur = d.currentStage;
    // id → name for showing stage assignees
    final names = {for (final m in (ref.watch(membersProvider).valueOrNull ?? [])) m.id: m.name};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // title + status
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(d.project.name, style: display(27, w: FontWeight.w600))),
        const SizedBox(width: 10),
        StatusPill(s.label, color: s.color),
      ]),
      const SizedBox(height: 16),

      // progress + delivery card
      AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${d.project.progressPct}', style: display(46, w: FontWeight.w600)),
              Text('%', style: display(22, w: FontWeight.w600, c: BT.mut)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Delivery', style: TextStyle(color: BT.mut, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(_d(d.targetDelivery), style: display(16, w: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 14),
          _track(cur?.name ?? 'Overall', d.project.progressPct, s.color),
        ]),
      ),

      const SizedBox(height: 12),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProjectRequirementsScreen(
            projectId: projectId, projectCode: d.project.code, editable: materialsEditable))),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(children: [
            Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.lav, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.inventory_2_rounded, size: 20, color: BT.ink)),
            const SizedBox(width: 13),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Materials & order-by', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              SizedBox(height: 2),
              Text('Parts this build needs · Hero #1 alerts', style: TextStyle(color: BT.mut, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
          ]),
        ),
      ),
      const SectionLabel('Build stages'),
      if (d.stages.isEmpty)
        const EmptyState(
          icon: Icons.timeline_rounded, tint: BT.amber,
          title: 'No stages yet',
          subtitle: 'Stages generate from the workflow template when the project is onboarded.')
      else
        ...List.generate(d.stages.length,
          (i) => _timelineTile(context, ref, d.stages[i], i == d.stages.length - 1, d.project.code, names)),
    ]);
  }

  // progress track: textured-free bar with a floating % pill.
  Widget _track(String label, int pct, Color pill) {
    final band = (0.34 + (pct / 100).clamp(0.0, 1.0) * 0.55).clamp(0.34, 0.93);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(height: 44, child: Stack(children: [
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(color: BT.track, borderRadius: BorderRadius.circular(999)))),
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis)))),
        Positioned.fill(child: Align(alignment: Alignment(band.toDouble() * 2 - 1, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: pill, borderRadius: BorderRadius.circular(999),
              boxShadow: const [BoxShadow(color: Color(0x1A695228), blurRadius: 8, offset: Offset(0, 3))]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text('$pct%', style: display(13, w: FontWeight.w600)),
            ])))),
      ])),
    );
  }

  Widget _timelineTile(BuildContext context, WidgetRef ref, Stage s, bool isLast, String code, Map<String, String> names) {
    final done = s.status == 'done';
    final now = s.status == 'in_progress';
    final todo = s.status == 'todo';

    final assignee = s.assigneeId == null ? null : names[s.assigneeId];
    final who = assignee ?? 'Unassigned';
    final subtitle = switch (s.status) {
      'done'        => 'Completed ${_d(s.actualEnd ?? s.plannedEnd)}${assignee != null ? ' · $assignee' : ''}',
      'in_progress' => 'In progress · $who',
      'rework'      => 'Rework · $who',
      _             => 'Starts ${_d(s.plannedStart)} · $who',
    };

    Widget dot;
    if (done) {
      dot = Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 13, color: BT.ink));
    } else if (now) {
      dot = Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle),
        child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
    } else {
      dot = Container(width: 22, height: 22,
        decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 1.5)));
    }

    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(children: [
        dot,
        if (!isLast) Expanded(child: Container(width: 2, color: BT.line,
          margin: const EdgeInsets.symmetric(vertical: 2))),
      ]),
      const SizedBox(width: 14),
      Expanded(child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, style: TextStyle(fontSize: 15,
            fontWeight: todo ? FontWeight.w500 : FontWeight.w600,
            color: todo ? BT.mut2 : BT.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: BT.mut)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StageDetailScreen(stage: s, projectCode: code))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BT.ink)),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, size: 16, color: BT.ink),
                ]),
              ),
            ),
            if (canAssign && s.status != 'done')
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openAssignSheet(context, s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_add_alt_1_rounded, size: 14, color: BT.lime),
                    const SizedBox(width: 5),
                    Text(assignee == null ? 'Assign' : 'Reassign',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ),
          ]),
        ]),
      )),
    ]));
  }

  /// Bottom sheet to assign / reassign / unassign a stage (PM only).
  void _openAssignSheet(BuildContext context, Stage stage) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final members = ref.watch(assignableMembersProvider);
        Future<void> apply(String? uid) async {
          await ref.read(projectsRepoProvider).assignStage(stage.id, uid);
          ref.invalidate(projectDetailProvider(projectId));
          ref.invalidate(workloadProvider);
          if (ctx.mounted) Navigator.pop(ctx);
        }
        return Container(
          decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
            Text('Assign · ${stage.name}', style: display(19, w: FontWeight.w600)),
            const SizedBox(height: 12),
            members.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => Text('Could not load team.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13)),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.people_outline_rounded, tint: BT.lav,
                    title: 'No assignable staff', subtitle: 'Add workshop/design/store/service members first.');
                }
                return Column(children: [
                  ...list.map((m) {
                    final selected = m.id == stage.assigneeId;
                    return Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => apply(m.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: selected ? BT.ink : BT.line, width: selected ? 1.5 : 1)),
                        child: Row(children: [
                          Container(width: 38, height: 38, alignment: Alignment.center,
                            decoration: BoxDecoration(color: roleColor(m.role), shape: BoxShape.circle),
                            child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: BT.ink))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.name.isEmpty ? m.email : m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 1),
                            Text(m.role, style: const TextStyle(color: BT.mut, fontSize: 12)),
                          ])),
                          if (selected) const Icon(Icons.check_circle_rounded, color: BT.ink, size: 20),
                        ]),
                      ),
                    ));
                  }),
                  if (stage.assigneeId != null) Padding(padding: const EdgeInsets.only(top: 4),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => apply(null),
                      child: Container(
                        width: double.infinity, alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(16)),
                        child: const Text('Unassign', style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700)),
                      ),
                    )),
                ]);
              },
            ),
          ]),
        );
      }),
    );
  }
}

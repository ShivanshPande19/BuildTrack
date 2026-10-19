import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/models.dart';

/// The disciplines a stage can be handed to. Order is the order a build
/// usually meets them in, which is the order the picker offers them.
const workflowDisciplines = ['design', 'workshop', 'store', 'service'];

String disciplineLabel(String? d) => switch (d) {
  'design'   => 'Design',
  'workshop' => 'Workshop',
  'store'    => 'Store',
  'service'  => 'Service',
  _          => 'Auto',
};

IconData disciplineIcon(String? d) => switch (d) {
  'design'   => Icons.palette_outlined,
  'workshop' => Icons.handyman_outlined,
  'store'    => Icons.inventory_2_outlined,
  'service'  => Icons.build_circle_outlined,
  _          => Icons.auto_awesome_outlined,
};

/// The spine down the left of a workflow: a numbered badge where a step
/// begins, and a short branch where a stage runs alongside the one above it.
///
/// The point is that the *shape* of the plan — what waits for what, what
/// happens at the same time — is visible without reading a single step number.
/// Builder and preview draw it with this one widget so they cannot disagree.
class StepRail extends StatelessWidget {
  final int step;
  /// False when this row runs alongside the one above.
  final bool startsStep;
  final bool isFirst, isLast;
  const StepRail({super.key, required this.step, required this.startsStep,
    required this.isFirst, required this.isLast});

  static const width = 34.0;
  static const _mid = 16.0;    // x of the spine
  static const _anchor = 24.0; // y the badge / branch sits at

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Stack(clipBehavior: Clip.none, children: [
      // The spine. It starts at the first badge and stops at the last, so the
      // line never trails off into nothing above or below the plan.
      Positioned(
        left: _mid, width: 2,
        top: isFirst ? _anchor : 0,
        bottom: isLast ? null : 0,
        height: isLast ? (isFirst ? 0 : _anchor) : null,
        child: const ColoredBox(color: BT.line)),
      if (startsStep)
        Positioned(
          left: _mid - 12, top: _anchor - 12,
          child: Container(
            width: 26, height: 26, alignment: Alignment.center,
            decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle),
            child: Text('$step', style: const TextStyle(color: Colors.white,
              fontSize: 12, fontWeight: FontWeight.w700))))
      else
        // A branch off the spine: "this happens alongside the stage above".
        Positioned(
          left: _mid, top: _anchor - 1,
          child: Container(width: width - _mid, height: 2,
            decoration: BoxDecoration(color: BT.sky,
              borderRadius: BorderRadius.circular(1)))),
    ]),
  );
}

/// A small coloured label for a stage's discipline, in that role's colour so a
/// workflow reads the same way the rest of the app colours its people.
class DisciplinePill extends StatelessWidget {
  final String? discipline;
  const DisciplinePill(this.discipline, {super.key});

  @override
  Widget build(BuildContext context) {
    final auto = discipline == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: auto ? BT.card2 : roleColor(discipline!).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: auto ? Border.all(color: BT.line) : null),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(disciplineIcon(discipline), size: 12, color: auto ? BT.mut : BT.ink),
        const SizedBox(width: 4),
        Text(disciplineLabel(discipline), style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700, color: auto ? BT.mut : BT.ink)),
      ]),
    );
  }
}

/// "3 checks · 2 parts · 15 jobs", leaving out whatever is empty.
String stageMeta(StageDraft s) {
  String n(int c, String one, String many) => '$c ${c == 1 ? one : many}';
  final checks = s.checks.where((c) => c.label.trim().isNotEmpty).length;
  final jobs = s.tasks.where((t) => t.title.trim().isNotEmpty).length;
  return [
    if (checks > 0) n(checks, 'check', 'checks'),
    if (s.items.isNotEmpty) n(s.items.length, 'part', 'parts'),
    if (jobs > 0) n(jobs, 'job', 'jobs'),
  ].join(' · ');
}

/// A read-only drawing of a whole workflow — the rail and a compact card per
/// stage. Used by the preview; the builder draws its own editable rows with
/// the same [StepRail].
class WorkflowFlow extends StatelessWidget {
  final List<StageDraft> stages;
  const WorkflowFlow({super.key, required this.stages});

  @override
  Widget build(BuildContext context) {
    final steps = stepsFor(stages);
    return Column(children: [
      for (var i = 0; i < stages.length; i++)
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StepRail(step: steps[i], startsStep: !stages[i].runsWithPrevious || i == 0,
            isFirst: i == 0, isLast: i == stages.length - 1),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(color: BT.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: stages[i].runsWithPrevious && i > 0
                    ? BT.sky : BT.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(stages[i].name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                  Text('${stages[i].days}d',
                    style: const TextStyle(fontSize: 12, color: BT.mut,
                      fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  DisciplinePill(stages[i].discipline),
                  const SizedBox(width: 8),
                  Expanded(child: Text(stageMeta(stages[i]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: BT.mut2))),
                ]),
              ]),
            ),
          )),
        ])),
    ]);
  }
}

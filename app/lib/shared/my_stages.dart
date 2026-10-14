import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../features/workshop/task_detail.dart';
import 'widgets.dart';

/// "My stages" — the stages the signed-in person has been assigned, with Start
/// work and Submit for approval on each.
///
/// Workshop has had this since the beginning, as its whole Tasks tab. Design and
/// Service never did, which is why a *Design & Layout* or *Testing & Delivery*
/// stage could be handed to them and then sit on `todo` forever: the RPCs
/// allowed it, nothing in their UI reached them. A build therefore never got
/// past the percentage its workshop stages accounted for, and handover needed
/// "Deliver anyway". Dropping this section into their home closes that loop
/// with the same screen, the same guards and the same approval chain.
///
/// `showInstallPart` is off here: scanning a part into a stage is a workshop
/// action, not a designer's.
class MyStagesSection extends ConsumerWidget {
  /// Shown above the list. "My design stages" / "My service stages".
  final String label;
  /// Design stages finish on the client's approval, not on the PM's alone
  /// (0028). The Design studio turns this on so the stage screen can say so.
  final bool designGate;
  /// What to say when there is nothing assigned — role-specific, because the
  /// reason is role-specific.
  final String emptySubtitle;
  final Color tint;
  const MyStagesSection({
    super.key,
    required this.label,
    required this.emptySubtitle,
    this.tint = BT.lav,
    this.designGate = false,
  });

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myTasksProvider);
    return tasks.when(
      // Quiet while loading: this sits below a section that already shows a
      // skeleton, and two shimmer blocks stacked read as a broken screen.
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ErrorCard('Could not load your stages.\n${friendlyError(e)}',
          onRetry: () => ref.invalidate(myTasksProvider)),
      ),
      data: (list) {
        // A stage the PM has already approved is history, not work.
        final open = list.where((t) => t.status != 'done').toList();
        // Capped: a designer carrying stages on eight builds needs the ones
        // that are late or sent back, not all eight, on a screen that is a
        // summary of their work. Sorted so the cap keeps the right ones —
        // rework first (someone is waiting on a fix), then overdue, then the
        // soonest due.
        final sorted = [...open]..sort((a, b) {
          int rank(WorkshopTask t) => t.status == 'rework' ? 0 : (t.isOverdue ? 1 : 2);
          final r = rank(a).compareTo(rank(b));
          if (r != 0) return r;
          final ad = a.assignedDue, bd = b.assignedDue;
          if (ad == null && bd == null) return a.projectCode.compareTo(b.projectCode);
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });

        return CappedSection(
          label: label,
          sheetTitle: label,
          max: 4,
          items: [
            for (final t in sorted) Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _StageCard(task: t, fmt: _fmt, designGate: designGate),
            ),
          ],
          empty: EmptyState(icon: Icons.assignment_outlined, tint: tint,
            title: 'No stages assigned', subtitle: emptySubtitle),
        );
      },
    );
  }
}

class _StageCard extends ConsumerWidget {
  final WorkshopTask task;
  final DateFormat fmt;
  final bool designGate;
  const _StageCard({required this.task, required this.fmt, this.designGate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = task.awaitingApproval
        ? (label: 'Awaiting approval', color: BT.amber)
        : task.status == 'rework'
            ? (label: 'Rework', color: BT.coral)
            : task.status == 'in_progress'
                ? (label: 'In progress', color: BT.lime)
                : (label: 'Not started', color: BT.mut2);

    return AppCard(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TaskDetailScreen(task: task,
            showInstallPart: false, designGate: designGate)));
        // Starting or submitting a stage changes this list, the PM's approvals
        // queue and the build's progress — refresh what the person can see.
        ref.invalidate(myTasksProvider);
        ref.invalidate(myAssignedBuildsProvider);
      },
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(task.stageName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          const SizedBox(width: 8),
          StatusPill(tone.label, color: tone.color),
        ]),
        const SizedBox(height: 4),
        Text([
          '${task.projectCode} · ${task.projectName}',
          if (task.assignedDue != null)
            task.isOverdue
              ? 'overdue — was due ${fmt.format(task.assignedDue!)}'
              : 'due ${fmt.format(task.assignedDue!)}',
        ].join(' · '),
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, height: 1.3,
            color: task.isOverdue ? BT.coral : BT.mut)),
        if (task.status == 'rework' && task.reworkNote != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
              borderRadius: BorderRadius.circular(11)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.replay_rounded, size: 15, color: BT.coral),
              const SizedBox(width: 8),
              Expanded(child: Text(task.reworkNote!,
                style: const TextStyle(fontSize: 12, height: 1.3, color: BT.ink))),
            ]),
          ),
        ],
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import '../../shared/workflow_visuals.dart';
import 'create_template.dart';

final _dayMonYear = DateFormat('d MMM yyyy');

/// Every saved workflow — how a build runs, stage by stage — for the admins
/// and PMs who plan builds. Reached from Settings.
///
/// A saved workflow is never edited: builds already running point at its
/// stages (0034). So the list offers two things only — make a new one, or open
/// one and start a new workflow from it.
class WorkflowsScreen extends ConsumerWidget {
  const WorkflowsScreen({super.key});

  Future<void> _create(BuildContext context, {String? from}) async {
    final created = await Navigator.of(context).push<OptRef>(
      MaterialPageRoute(builder: (_) => CreateTemplate(startFrom: from)));
    if (created != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved "${created.label}". It is ready to pick when onboarding a build.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(workflowSummariesProvider);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        color: BT.ink,
        onRefresh: () => ref.refresh(workflowSummariesProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(children: [
              const BackChip(),
              const Spacer(),
              PressableScale(
                onTap: () => _create(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(999)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 5),
                    Text('New', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Colors.white)),
                  ]))),
            ]),
            const SizedBox(height: 18),
            Text('Workflows', style: display(28, w: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('How a build runs, stage by stage. Pick one when you onboard a '
                       'build or set up its plan.',
              style: TextStyle(fontSize: 13, color: BT.mut, height: 1.35)),
            const SizedBox(height: 18),
            ...list.when(
              loading: () => [const SkeletonList(count: 3)],
              error: (e, _) => [ErrorCard('Could not load workflows.\n${friendlyError(e)}',
                onRetry: () => ref.invalidate(workflowSummariesProvider))],
              data: (ws) => ws.isEmpty
                ? [
                    const EmptyState(icon: Icons.account_tree_outlined, tint: BT.sky,
                      title: 'No workflows yet',
                      subtitle: 'Plan how a build runs once, then use it for every build like it.'),
                    PrimaryButton('Create the first workflow', icon: Icons.add_rounded,
                      onTap: () => _create(context)),
                  ]
                : [
                    for (var i = 0; i < ws.length; i++)
                      FadeSlideIn(
                        key: ValueKey(ws[i].id),
                        delay: Motion.stagger(i.clamp(0, 8)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WorkflowCard(ws[i], onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => WorkflowPreview(summary: ws[i])))))),
                  ],
            ),
          ],
        ),
      )),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  final WorkflowSummary w;
  final VoidCallback onTap;
  const _WorkflowCard(this.w, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final by = [
      if (w.createdByName != null) 'by ${w.createdByName}',
      if (w.createdAt != null) _dayMonYear.format(w.createdAt!.toLocal()),
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
      child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.sky.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.account_tree_outlined, size: 20, color: BT.ink)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (w.truckType != null) ...[
            const SizedBox(height: 1),
            Text(w.truckType!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: BT.mut)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Fact('${w.stageCount} ${w.stageCount == 1 ? 'stage' : 'stages'}'),
            _Fact('${w.stepCount} ${w.stepCount == 1 ? 'step' : 'steps'}'),
            _Fact('~${w.estimatedDays} ${w.estimatedDays == 1 ? 'day' : 'days'}'),
          ]),
          if (by.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(by, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: BT.mut2)),
          ],
        ])),
        const Icon(Icons.chevron_right_rounded, color: BT.mut2),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final String text;
  const _Fact(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)));
}

/// One workflow, drawn in full: every stage on the rail, what runs together,
/// what each stage carries. Read-only — the way to change it is a new
/// workflow started from it.
class WorkflowPreview extends ConsumerWidget {
  final WorkflowSummary summary;
  const WorkflowPreview({super.key, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(workflowDraftsProvider(summary.id));
    final w = summary;
    return Scaffold(
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: BT.bg,
          border: Border(top: BorderSide(color: BT.line))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: PrimaryButton('Start a new workflow from this', icon: Icons.copy_all_rounded,
            onTap: () async {
              final created = await Navigator.of(context).push<OptRef>(
                MaterialPageRoute(builder: (_) => CreateTemplate(startFrom: w.id)));
              if (created != null && context.mounted) {
                // Back to the list, where the new one is now at the top.
                Navigator.of(context).pop();
              }
            }),
        )),
      ),
      body: SafeArea(bottom: false, child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Row(children: [BackChip()]),
          const SizedBox(height: 18),
          const Text('WORKFLOW', style: TextStyle(fontSize: 11, letterSpacing: 1.4,
            color: BT.mut, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(w.name, style: display(26, w: FontWeight.w600)),
          if (w.truckType != null) ...[
            const SizedBox(height: 2),
            Text(w.truckType!, style: const TextStyle(fontSize: 13, color: BT.mut)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            _bigStat(w.stageCount, w.stageCount == 1 ? 'stage' : 'stages'),
            _bigStat(w.stepCount, w.stepCount == 1 ? 'step' : 'steps'),
            _bigStat(w.estimatedDays, w.estimatedDays == 1 ? 'day' : 'days', prefix: '~'),
          ]),
          if (w.createdByName != null || w.createdAt != null) ...[
            const SizedBox(height: 12),
            Text([
              'Made',
              if (w.createdByName != null) 'by ${w.createdByName}',
              if (w.createdAt != null) 'on ${_dayMonYear.format(w.createdAt!.toLocal())}',
            ].join(' '), style: const TextStyle(fontSize: 12, color: BT.mut2)),
          ],
          const SectionLabel('The flow'),
          drafts.when(
            loading: () => const SkeletonList(count: 4),
            error: (e, _) => ErrorCard('Could not load this workflow.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(workflowDraftsProvider(w.id))),
            data: (d) => FadeSlideIn(child: WorkflowFlow(stages: d.stages)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: BT.mut),
              SizedBox(width: 10),
              Expanded(child: Text(
                'A saved workflow does not change — builds already running follow it. '
                'To plan it differently, start a new workflow from this one.',
                style: TextStyle(fontSize: 12, color: BT.mut, height: 1.35))),
            ]),
          ),
        ],
      )),
    );
  }

  Widget _bigStat(int n, String label, {String prefix = ''}) => Expanded(child: Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: BT.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
        children: [
          if (prefix.isNotEmpty) Text(prefix, style: display(18, w: FontWeight.w600, c: BT.mut)),
          CountUp(n, style: display(22, w: FontWeight.w700)),
        ]),
      Text(label, style: const TextStyle(fontSize: 11, color: BT.mut, fontWeight: FontWeight.w600)),
    ]),
  ));
}

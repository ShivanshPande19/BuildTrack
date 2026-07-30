import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../admin/project_detail.dart' show openAssignSheet;

/// PM — Assign work: every stage across the PM's builds that still needs an
/// owner, grouped by build.
///
/// This is the PM's core job (step 4 of the chain) and there was previously no
/// single place to do it — you had to open each project and hunt through its
/// timeline. The ＋ button on the PM shell lands here.
class AssignWorkScreen extends ConsumerWidget {
  const AssignWorkScreen({super.key});

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(stagesToAssignProvider);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(stagesToAssignProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
            ]),
            const SizedBox(height: 14),
            Text('Assign work', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Stages on your builds that still need an owner.',
              style: TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 16),
            pending.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.task_alt_rounded, tint: BT.lime,
                    title: 'Everything is assigned',
                    subtitle: 'Every stage on your builds has an owner. Nice.');
                }
                // group by build so the PM works one truck at a time
                final byProject = <String, List<AssignableStage>>{};
                for (final a in list) {
                  byProject.putIfAbsent(a.projectId, () => []).add(a);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final entry in byProject.entries) ...[
                    SectionLabel('${entry.value.first.projectCode} · ${entry.value.first.projectName}'),
                    ...entry.value.map((a) => _tile(context, ref, a)),
                  ],
                ]);
              },
            ),
          ],
        ),
      )),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, AssignableStage a) {
    final s = a.stage;
    final rework = s.status == 'rework';
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rework ? BT.coral : roleColor(s.discipline ?? 'workshop'),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(rework ? Icons.replay_rounded : Icons.handyman_rounded,
              size: 19, color: BT.ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text([
              if (s.discipline != null) s.discipline!,
              if (rework) 'needs rework' else 'unassigned',
              if (s.plannedStart != null) 'planned ${_fmt.format(s.plannedStart!)}',
            ].join(' · '), style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 12),
        PrimaryButton('Assign', icon: Icons.person_add_alt_1_rounded, bg: BT.ink, fg: Colors.white,
          onTap: () => openAssignSheet(context, ref, s, a.projectId, onDone: () {
            ref.invalidate(stagesToAssignProvider);
            ref.invalidate(projectDetailProvider(a.projectId));
            ref.invalidate(workloadProvider);
          })),
      ]),
    ));
  }
}

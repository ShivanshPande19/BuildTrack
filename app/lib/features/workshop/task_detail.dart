import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'scan_install.dart';

/// Workshop — task (stage) detail: checklist, photos, install parts, submit for approval.
class TaskDetailScreen extends ConsumerWidget {
  final WorkshopTask task;
  const TaskDetailScreen({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(stageBundleProvider(task.stageId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(stageBundleProvider(task.stageId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Text(task.projectCode, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            Text(task.stageName, style: display(27, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(task.projectName, style: const TextStyle(color: BT.mut, fontSize: 13)),
            const SizedBox(height: 16),
            bundle.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load task.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (b) => _content(context, ref, b),
            ),
          ],
        ),
      )),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, StageBundle b) {
    final total = b.checklist.length;
    final done = b.checklist.where((c) => c.done).length;
    final pct = total == 0 ? 0 : (done / total * 100).round();
    final allDone = total > 0 && done == total;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // progress
      AppCard(padding: const EdgeInsets.fromLTRB(18, 16, 18, 18), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('PROGRESS', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: BT.mut, fontWeight: FontWeight.w600)),
          Text('$pct%', style: display(15, w: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(
          value: total == 0 ? 0 : done / total, minHeight: 10,
          backgroundColor: BT.track, valueColor: const AlwaysStoppedAnimation(BT.lime))),
      ])),

      // checklist
      const SectionLabel('Checklist'),
      if (b.checklist.isEmpty)
        const EmptyState(icon: Icons.checklist_rounded, tint: BT.lime, title: 'No checklist', subtitle: 'This stage has no checklist items.')
      else
        AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Column(
          children: b.checklist.map((c) => _checkRow(context, ref, c)).toList())),

      // actions
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _btn('Photo', Icons.photo_camera_outlined, false, () => _addPhoto(context, ref))),
        const SizedBox(width: 11),
        Expanded(child: _btn('Install part', Icons.qr_code_scanner_rounded, false, () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanInstall(task: task))))),
      ]),
      const SizedBox(height: 11),
      _btn(allDone ? 'Submit for approval' : 'Mark stage complete', Icons.check_rounded, true, () => _submit(context, ref)),
      if (!allDone && total > 0) Padding(padding: const EdgeInsets.only(top: 10),
        child: Text('$done of $total checks done — finish all before final approval.',
          textAlign: TextAlign.center, style: const TextStyle(color: BT.mut, fontSize: 12))),

      // installed parts on this stage
      if (b.parts.isNotEmpty) ...[
        const SectionLabel('Parts installed'),
        ...b.parts.map((p) => Padding(padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Row(children: [
            const Icon(Icons.memory_rounded, size: 20, color: BT.ink),
            const SizedBox(width: 12),
            Expanded(child: Text(p.model.isEmpty ? p.name : '${p.name} · ${p.model}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            Text(p.serial, style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])))),
      ],
    ]);
  }

  Widget _checkRow(BuildContext context, WidgetRef ref, ChecklistItem c) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () async {
      await ref.read(workshopRepoProvider).toggleChecklist(c.id, !c.done);
      ref.invalidate(stageBundleProvider(task.stageId));
    },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(children: [
        Container(width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.done ? BT.lime : Colors.transparent, borderRadius: BorderRadius.circular(9),
            border: c.done ? null : Border.all(color: BT.mut2, width: 2)),
          child: c.done ? const Icon(Icons.check_rounded, size: 15, color: BT.ink) : null),
        const SizedBox(width: 13),
        Expanded(child: Text(c.label, style: TextStyle(fontSize: 14.5,
          color: c.done ? BT.mut2 : BT.ink,
          decoration: c.done ? TextDecoration.lineThrough : null, decorationColor: BT.mut2))),
      ]),
    ),
  );

  Future<void> _addPhoto(BuildContext context, WidgetRef ref) async {
    final noteC = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Add photo', style: display(18, w: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Camera upload comes later — this attaches a work photo with your note.',
          style: TextStyle(color: BT.mut, fontSize: 12.5)),
        const SizedBox(height: 10),
        Container(decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(controller: noteC, decoration: const InputDecoration(hintText: 'Note (optional)', border: InputBorder.none))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    ));
    if (ok == true) {
      await ref.read(workshopRepoProvider).addStagePhoto(task.stageId, noteC.text.trim());
      ref.invalidate(stageBundleProvider(task.stageId));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: BT.ink, content: Text('Photo attached')));
    }
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(workshopRepoProvider).submitForApproval(task.stageId);
      ref.invalidate(pendingApprovalsProvider);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Submitted for PM approval')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text('Failed: $e')));
    }
  }

  Widget _btn(String label, IconData icon, bool dark, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(height: 54, alignment: Alignment.center,
      decoration: BoxDecoration(color: dark ? BT.ink : BT.card, borderRadius: BorderRadius.circular(16),
        border: dark ? null : Border.all(color: BT.line)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 19, color: dark ? BT.lime : BT.ink),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: dark ? Colors.white : BT.ink)),
      ])),
  );
}

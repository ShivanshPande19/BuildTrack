import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import '../../shared/photo_picker.dart';
import 'scan_install.dart';

/// Workshop — task (stage) detail: checklist, photos, install parts, submit for approval.
class TaskDetailScreen extends ConsumerWidget {
  final WorkshopTask task;
  const TaskDetailScreen({super.key, required this.task});

  static final _fmt = DateFormat('d MMM');
  String _shortDate(DateTime d) => _fmt.format(d);

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
              const BackChip(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Text(task.projectCode, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            Text(task.stageName, style: display(27, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(task.projectName, style: const TextStyle(color: BT.mut, fontSize: 13)),
            const SizedBox(height: 16),
            ContentReveal(child: bundle.when(
              loading: () => const SkeletonList(count: 3),
              error: (e, _) => ErrorCard('Could not load task.\n${friendlyError(e)}', onRetry: () => ref.invalidate(stageBundleProvider(task.stageId))),
              data: (b) => _content(context, ref, b),
            )),
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
      // what the PM asked for when handing this over
      if (task.status == 'rework') ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
            borderRadius: BorderRadius.circular(BT.radiusCard)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.replay_rounded, size: 19, color: BT.coral),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sent back for rework',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(task.reworkNote ?? 'Your PM asked for changes on this stage.',
                style: const TextStyle(fontSize: 12.5, color: BT.ink, height: 1.35)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
      ] else if (task.assignedDue != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(color: task.isOverdue ? const Color(0xFFFBE4E0) : BT.card2,
            borderRadius: BorderRadius.circular(BT.radiusCard)),
          child: Row(children: [
            Icon(Icons.flag_rounded, size: 17, color: task.isOverdue ? BT.coral : BT.mut),
            const SizedBox(width: 9),
            Text(task.isOverdue ? 'Overdue — was due ${_shortDate(task.assignedDue!)}'
                               : 'Due ${_shortDate(task.assignedDue!)}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: task.isOverdue ? BT.coral : BT.ink)),
          ]),
        ),
        const SizedBox(height: 12),
      ],

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
          children: [
            // No divider under the last row (it doubled up with the card's edge).
            for (var i = 0; i < b.checklist.length; i++)
              _ChecklistTile(key: ValueKey(b.checklist[i].id), c: b.checklist[i], stageId: task.stageId,
                divider: i < b.checklist.length - 1),
          ])),

      // actions
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: SecondaryButton('Photo', icon: Icons.photo_camera_outlined, onTap: () => _addPhoto(context, ref))),
        const SizedBox(width: 11),
        Expanded(child: SecondaryButton('Install part', icon: Icons.qr_code_scanner_rounded, onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanInstall(task: task))))),
      ]),
      const SizedBox(height: 11),
      if (task.awaitingApproval)
        // Nothing to do until the PM decides — offering Submit again would just
        // bounce off the duplicate-submission guard.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(color: BT.amber.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
          child: const Row(children: [
            Icon(Icons.hourglass_top_rounded, size: 19, color: BT.ink),
            SizedBox(width: 10),
            Expanded(child: Text('Waiting for your PM to approve this stage.',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3))),
          ]),
        )
      else if (task.canStart)
        // The transition nothing used to make: until a stage is started it stays
        // 'todo', which kept it out of the PM's day view and the workload numbers.
        // AsyncPrimaryButton: a double-tap on site can't start or submit twice.
        AsyncPrimaryButton('Start work', icon: Icons.play_arrow_rounded, bg: BT.ink, fg: Colors.white,
          onTap: () => _start(context, ref))
      else
        AsyncPrimaryButton(allDone || total == 0 ? 'Submit for approval' : 'Mark stage complete',
          icon: Icons.check_rounded, bg: BT.ink, fg: Colors.white,
          onTap: () => _submit(context, ref)),
      if (!task.awaitingApproval && !task.canStart && !allDone && total > 0)
        Padding(padding: const EdgeInsets.only(top: 10),
          // Full width so textAlign.center actually centres it (it sat left).
          child: SizedBox(width: double.infinity, child: Text('$done of $total checks done — finish all before final approval.',
            textAlign: TextAlign.center, style: const TextStyle(color: BT.mut, fontSize: 12)))),

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

  /// Take (or pick) a real photo, caption it, and upload it to the `builds`
  /// bucket. The client sees these on their stage timeline, so they used to be
  /// looking at random stock images from picsum.photos.
  Future<void> _addPhoto(BuildContext context, WidgetRef ref) async {
    final photo = await pickPhoto(context);
    if (photo == null || !context.mounted) return;

    final noteC = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Add photo', style: display(18, w: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(photo.bytes, height: 150, width: double.infinity, fit: BoxFit.cover),
        ),
        const SizedBox(height: 12),
        Container(decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(controller: noteC,
            decoration: const InputDecoration(hintText: 'Caption (optional)', border: InputBorder.none))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false),
          child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Upload', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    ));
    if (ok != true || !context.mounted) return;

    // Uploads on site can be slow — say so instead of looking frozen.
    final bar = ScaffoldMessenger.of(context);
    bar.showSnackBar(const SnackBar(backgroundColor: BT.ink,
      duration: Duration(minutes: 1), content: Row(children: [
        SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: BT.lime)),
        SizedBox(width: 12),
        Text('Uploading photo…'),
      ])));
    try {
      await ref.read(workshopRepoProvider).addStagePhoto(task.stageId, photo.bytes,
        filename: photo.filename, contentType: photo.contentType, caption: noteC.text);
      ref.invalidate(stageBundleProvider(task.stageId));
      ref.invalidate(truckPhotosProvider(task.projectId));
      ref.invalidate(stagePhotosProvider(task.stageId));
      bar.clearSnackBars();
      bar.showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Photo uploaded')));
    } catch (e) {
      bar.clearSnackBars();
      bar.showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(workshopRepoProvider).startTask(task.stageId);
      ref.invalidate(myTasksProvider);
      ref.invalidate(stageBundleProvider(task.stageId));
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Stage started — your PM has been told')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(workshopRepoProvider).submitForApproval(task.stageId);
      ref.invalidate(pendingApprovalsProvider);
      ref.invalidate(myTasksProvider);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Submitted for PM approval')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }
}


/// One checklist row. Toggling is optimistic (the tick flips immediately, so a
/// slow workshop connection doesn't feel dead), guarded against a re-tap while
/// the write is in flight, and surfaces a failure instead of silently swallowing
/// it — the old inline toggle did none of these, so a failed write looked like
/// the checkbox just wouldn't tick and the user kept tapping.
class _ChecklistTile extends ConsumerStatefulWidget {
  final ChecklistItem c;
  final String stageId;
  final bool divider;
  const _ChecklistTile({super.key, required this.c, required this.stageId, this.divider = true});
  @override
  ConsumerState<_ChecklistTile> createState() => _ChecklistTileState();
}

class _ChecklistTileState extends ConsumerState<_ChecklistTile> {
  bool? _optimistic; // set while a toggle is pending / until the refetch agrees
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _ChecklistTile old) {
    super.didUpdateWidget(old);
    // Server refetch landed with a new value — let it be the source of truth again.
    if (old.c.done != widget.c.done) _optimistic = null;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final target = !(_optimistic ?? widget.c.done);
    setState(() { _optimistic = target; _busy = true; });
    Haptic.tap();
    try {
      await ref.read(workshopRepoProvider).toggleChecklist(widget.c.id, target);
      ref.invalidate(stageBundleProvider(widget.stageId));
    } catch (e) {
      if (!mounted) return; // reverts nothing / shows nothing if we're gone
      setState(() => _optimistic = null); // revert the tick
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: BT.coral, content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _optimistic ?? widget.c.done;
    // The tick is optimistic and instant: the box fills, the check pops in
    // with a small overshoot, and the label fades to struck-through, all
    // before the server answers.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: widget.divider ? const Border(bottom: BorderSide(color: BT.line)) : null),
        child: Row(children: [
          AnimatedContainer(
            duration: Motion.fast, curve: Motion.move,
            width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: done ? BT.lime : Colors.transparent, borderRadius: BorderRadius.circular(9),
              border: Border.all(color: done ? BT.lime : BT.mut2, width: 2)),
            child: AnimatedScale(
              scale: done ? 1 : 0,
              duration: done ? Motion.base : Motion.fast,
              curve: done ? Curves.easeOutBack : Motion.exit,
              child: const Icon(Icons.check_rounded, size: 15, color: BT.ink))),
          const SizedBox(width: 13),
          Expanded(child: AnimatedDefaultTextStyle(
            duration: Motion.fast,
            // Merge onto the ambient style so the app font is kept.
            style: DefaultTextStyle.of(context).style.merge(TextStyle(fontSize: 14.5,
              color: done ? BT.mut2 : BT.ink,
              decoration: done ? TextDecoration.lineThrough : TextDecoration.none, decorationColor: BT.mut2)),
            child: Text(widget.c.label))),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';
import '../../shared/photo_picker.dart';
import '../../shared/document_viewer.dart';
import '../admin/truck_record.dart';
import 'scan_install.dart';

/// Stage detail for whoever the stage is assigned to: checklist, site photos,
/// parts installed, Start work and Submit for approval.
///
/// Not workshop-only. `fn_start_stage` / `fn_submit_stage` have always accepted
/// any assignee, but this screen was reachable only from the Workshop tab — so a
/// *Design & Layout* or *Testing & Delivery* stage assigned to a designer or a
/// service member could never be started or submitted, the build's progress
/// never reached 100%, and handover needed "Deliver anyway". Design and Service
/// open the same screen now, with [showInstallPart] off: scanning a part into a
/// stage is a workshop action, and offering it to a designer is noise.
class TaskDetailScreen extends ConsumerWidget {
  final WorkshopTask task;
  final bool showInstallPart;
  /// Set on a **design** stage. Its deliverable is a design the client has
  /// approved (0028 refuses the submit otherwise), so the screen says so before
  /// the button is pressed rather than letting the database say it afterwards.
  final bool designGate;
  const TaskDetailScreen({super.key, required this.task,
    this.showInstallPart = true, this.designGate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The stage as it stands now, not as it was when the screen opened. Start
    // work keeps you here — starting is the beginning of the work, not the end
    // of it — so the screen has to follow the stage on to in progress, and the
    // bar under the thumb on to Submit. Every way in hands over a row of
    // myTasksProvider; the one passed in covers a stage that has since left
    // the list.
    final live = ref.watch(myTasksProvider.select((a) =>
        a.valueOrNull?.where((t) => t.stageId == task.stageId).firstOrNull)) ?? task;
    return _TaskDetailView(task: live,
      showInstallPart: showInstallPart, designGate: designGate);
  }
}

class _TaskDetailView extends ConsumerWidget {
  final WorkshopTask task;
  final bool showInstallPart;
  final bool designGate;
  const _TaskDetailView({required this.task,
    required this.showInstallPart, required this.designGate});

  static final _fmt = DateFormat('d MMM');
  String _shortDate(DateTime d) => _fmt.format(d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(stageBundleProvider(task.stageId));
    return Scaffold(
      // The primary action is pinned, not scrolled to.
      //
      // It used to sit in the middle of the page — after the checklist and the
      // materials, but before the photos, the delays, the installed parts and
      // the truck record — so the screen read as a pile rather than an order,
      // and "submit" was something you scrolled past on the way to the bottom.
      // Everything above is now what the stage *is*; the one thing you do with
      // it is always within reach.
      bottomNavigationBar: bundle.hasValue
        ? _actionBar(context, ref, bundle.value!)
        : null,
      body: SafeArea(bottom: false, child: RefreshIndicator(
        onRefresh: () async => ref.refresh(stageBundleProvider(task.stageId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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

  /// A section heading with the action that belongs to it on the same line.
  ///
  /// Every action used to live in one block in the middle of the page, away
  /// from the thing it affected — "Photo" nowhere near the photos, "Install
  /// part" nowhere near the parts. Put each one on its own section and the
  /// page stops needing to be learned.
  Widget _sectionHeader(String label, {String? action, VoidCallback? onAction}) =>
    Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(children: [
        Expanded(child: Text(label.toUpperCase(),
          style: const TextStyle(fontSize: 11, letterSpacing: 1.2,
            color: BT.mut, fontWeight: FontWeight.w600))),
        if (action != null && onAction != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, size: 15, color: BT.ink),
                const SizedBox(width: 3),
                Text(action, style: const TextStyle(fontSize: 12.5,
                  fontWeight: FontWeight.w700, color: BT.ink)),
              ]),
            ),
          ),
      ]),
    );

  Widget _content(BuildContext context, WidgetRef ref, StageBundle b) {
    final total = b.checklist.length;
    final done = b.checklist.where((c) => c.done).length;
    final pct = total == 0 ? 0 : (done / total * 100).round();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Where this stage stands ──────────────────────────────────────
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
      ] else if (task.isWaitingOnEarlierWork) ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: BT.card2,
            borderRadius: BorderRadius.circular(BT.radiusCard),
            border: Border.all(color: BT.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline_rounded, size: 19, color: BT.mut),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.waitingLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(task.assignedDue == null
                  ? 'You can look at what it needs, but it cannot be started yet.'
                  : 'Due ${_shortDate(task.assignedDue!)}. You can look at what it '
                    'needs, but it cannot be started yet.',
                style: const TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
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

      // ── The work ─────────────────────────────────────────────────────
      _sectionHeader('Checklist'),
      if (b.checklist.isEmpty)
        const EmptyState(icon: Icons.checklist_rounded, tint: BT.lime, title: 'No checklist', subtitle: 'This stage has no checklist items.')
      else
        AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Column(
          children: [
            // No divider under the last row (it doubled up with the card's edge).
            for (var i = 0; i < b.checklist.length; i++)
              _ChecklistTile(key: ValueKey(b.checklist[i].id), c: b.checklist[i], stageId: task.stageId,
                projectId: task.projectId,
                photos: b.photos, frozen: task.isClosed,
                divider: i < b.checklist.length - 1),
          ])),
      if (b.proofOutstanding > 0)
        Padding(padding: const EdgeInsets.only(top: 9, left: 4),
          child: Row(children: [
            const Icon(Icons.photo_camera_outlined, size: 14, color: BT.mut),
            const SizedBox(width: 7),
            Expanded(child: Text(
              '${b.proofOutstanding} ${b.proofOutstanding == 1 ? 'check needs' : 'checks need'} '
              'a photo before ${b.proofOutstanding == 1 ? 'it' : 'they'} can be ticked.',
              style: const TextStyle(fontSize: 12, color: BT.mut, height: 1.3))),
          ])),

      // ── Who is doing what ────────────────────────────────────────────
      //
      // A workshop stage is a fortnight of work by several people. The person
      // the PM handed it to breaks it down here and gives each piece to
      // somebody; everyone else sees it read-only, which is how a PM watches
      // progress without assigning fifteen items by name across forty builds.
      if (showInstallPart) _SubStages(task: task, frozen: task.isClosed),

      // ── What this stage is built from ────────────────────────────────
      if (b.materials.isNotEmpty) ...[
        _sectionHeader('Parts this stage needs'),
        AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Column(
          children: [
            for (var i = 0; i < b.materials.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: i < b.materials.length - 1
                    ? const Border(bottom: BorderSide(color: BT.line)) : null),
                child: Row(children: [
                  Icon(b.materials[i].isReceived
                      ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    size: 16, color: b.materials[i].isReceived ? BT.lime : BT.mut2),
                  const SizedBox(width: 11),
                  Expanded(child: Text(b.materials[i].name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  Text('×${b.materials[i].qty}',
                    style: const TextStyle(fontSize: 12.5, color: BT.mut)),
                  const SizedBox(width: 10),
                  StatusPill(
                    switch (b.materials[i].status) {
                      'received' => 'In store',
                      'ordered'  => 'On order',
                      _          => 'Not ordered',
                    },
                    color: switch (b.materials[i].status) {
                      'received' => BT.lime,
                      'ordered'  => BT.sky,
                      _          => BT.card2,
                    }),
                ]),
              ),
          ])),
      ],

      // ── What you have recorded ───────────────────────────────────────
      _sectionHeader(
        b.photos.isEmpty ? 'Photos' : 'Photos · ${b.photos.length}',
        action: task.isClosed ? null : (showInstallPart ? 'Add photo' : 'Add reference'),
        onAction: task.isClosed ? null : () => _addPhoto(context, ref)),
      if (b.photos.isEmpty)
        EmptyState(icon: Icons.photo_camera_outlined, tint: BT.card2,
          title: task.isClosed ? 'No photos on this stage' : 'No photos yet',
          subtitle: showInstallPart
            ? 'Your project manager and the client see these as the evidence of the work.'
            : 'Attach a reference your project manager should see.')
      else
        SizedBox(height: 118, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: b.photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _PhotoThumb(
            photo: b.photos[i],
            // Removing a photo is the PM's or the person who took it — and
            // nobody's once the stage is signed off (0030).
            onDelete: task.isClosed || b.photos[i].id == null
              ? null
              : () => _deletePhoto(context, ref, b, b.photos[i]),
          ),
        )),

      if (showInstallPart) ...[
        _sectionHeader(
          b.parts.isEmpty ? 'Parts fitted here' : 'Parts fitted here · ${b.parts.length}',
          action: task.isClosed ? null : 'Install part',
          onAction: task.isClosed ? null : () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanInstall(task: task)))),
        if (b.parts.isEmpty)
          const EmptyState(icon: Icons.memory_outlined, tint: BT.card2,
            title: 'Nothing fitted yet',
            subtitle: 'Scan a part\'s label to record it against this stage.')
        else
          AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Column(
            children: [
              for (var i = 0; i < b.parts.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(border: i < b.parts.length - 1
                      ? const Border(bottom: BorderSide(color: BT.line)) : null),
                  child: Row(children: [
                    const Icon(Icons.memory_rounded, size: 19, color: BT.ink),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      b.parts[i].model.isEmpty ? b.parts[i].name : '${b.parts[i].name} · ${b.parts[i].model}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                    Text(b.parts[i].serial, style: const TextStyle(color: BT.mut, fontSize: 12)),
                  ]),
                ),
            ])),
      ],

      // ── Why it slipped ───────────────────────────────────────────────
      if (!task.isClosed || b.delays.isNotEmpty)
        _sectionHeader(
          b.delays.isEmpty ? 'Hold-ups' : 'Hold-ups · ${b.delays.length}',
          action: task.isClosed || task.canStart ? null : 'Report one',
          onAction: task.isClosed || task.canStart ? null : () => _logDelay(context, ref)),
      if (b.delays.isNotEmpty)
        for (final d in b.delays)
          Padding(padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.schedule_rounded, size: 17, color: BT.coral),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.reason} · ${d.days} day${d.days == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  if (d.note != null && d.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(d.note!.trim(),
                      style: const TextStyle(fontSize: 12.5, color: BT.mut, height: 1.3)),
                  ],
                ])),
              ])))
      else if (!task.isClosed && !task.canStart)
        Padding(padding: const EdgeInsets.only(left: 4),
          child: Text(
            'If something is holding this stage up — parts, a drawing, capacity — '
            'say so and your project manager sees it on the build.',
            style: const TextStyle(fontSize: 12, color: BT.mut, height: 1.35))),

      // ── The whole truck ──────────────────────────────────────────────
      if (showInstallPart) ...[
        const SizedBox(height: 22),
        AppCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TruckRecordScreen(projectId: task.projectId,
              code: task.projectCode, name: task.projectName))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(children: [
            Container(width: 38, height: 38, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.sky, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.fact_check_outlined, size: 19, color: Color(0xFF123040))),
            const SizedBox(width: 13),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This truck\'s full record',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              SizedBox(height: 2),
              Text('Every part fitted so far, its serial and who fitted it.',
                style: TextStyle(fontSize: 12, color: BT.mut)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: BT.mut),
          ])),
      ],
    ]);
  }

  /// The pinned bar: the one thing to do with this stage, and why you cannot.
  Widget _actionBar(BuildContext context, WidgetRef ref, StageBundle b) {
    final total = b.checklist.length;
    final done = b.checklist.where((c) => c.done).length;
    final allDone = total > 0 && done == total;

    Widget wrap(Widget child, {String? hint}) => Container(
      decoration: const BoxDecoration(
        color: BT.bg, border: Border(top: BorderSide(color: BT.line))),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          child,
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, textAlign: TextAlign.center,
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ],
        ]),
      )),
    );

    Widget notice(IconData icon, String title, String body, {Color tint = BT.card2}) => wrap(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: tint,
          borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: BT.mut),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 3),
            Text(body, style: const TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
          ])),
        ]),
      ));

    if (task.isDelivered) {
      return notice(Icons.local_shipping_outlined, 'This truck has been delivered',
        'The build was closed with this stage still open. It is kept as a record — '
        'talk to your project manager if work is still needed.');
    }
    if (task.awaitingApproval) {
      // Offering Submit again would just bounce off the duplicate guard.
      return notice(Icons.hourglass_top_rounded, 'With your project manager',
        'They have your submission. Nothing to do here until they decide.',
        tint: BT.amber.withValues(alpha: 0.35));
    }
    if (task.isWaitingOnEarlierWork) {
      // Not a disabled Start button: a button that does nothing explains
      // nothing. A build runs in steps (0031) and this one's turn has not come,
      // so the bar says whose has — the stage that has to be approved before
      // this one opens. fn_start_stage would refuse it anyway.
      return notice(Icons.lock_outline_rounded, task.waitingLabel,
        task.blockedByCount > 1
          ? 'This stage opens once the earlier stages on this build are approved. '
            'Your project manager can regroup them if they really do run together.'
          : 'This stage opens once "${task.blockedBy}" is approved. Your project '
            'manager can group the two if they really do run at the same time.');
    }
    if (task.canStart) {
      // The transition nothing used to make: until a stage is started it stays
      // 'todo', which kept it out of the PM's day view and the workload numbers.
      // AsyncPrimaryButton: a double-tap on site can't start or submit twice.
      return wrap(AsyncPrimaryButton('Start work', icon: Icons.play_arrow_rounded,
        bg: BT.ink, fg: Colors.white, onTap: () => _start(context, ref)));
    }
    if (designGate && !_designApproved(ref)) {
      // Not a disabled button: a button that does nothing explains nothing.
      return notice(Icons.palette_outlined, 'Waiting on the client', _designHint(ref));
    }
    return wrap(
      AsyncPrimaryButton(allDone || total == 0 ? 'Submit for approval' : 'Submit with checks open',
        icon: Icons.check_rounded, bg: BT.ink, fg: Colors.white,
        // With checks still open the button used to read "Mark stage complete"
        // and submit regardless — the PM then got a submission whose own
        // checklist said it wasn't finished. It still goes through (sometimes a
        // check genuinely doesn't apply), but deliberately.
        onTap: () => _submit(context, ref, openChecks: total - done)),
      hint: allDone || total == 0
        ? null
        : '$done of $total checks done — finish all before final approval.');
  }

  /// Remove a photo, saying what it costs before it is gone.
  Future<void> _deletePhoto(
      BuildContext context, WidgetRef ref, StageBundle b, StagePhoto photo) async {
    // A photo can be the proof that discharged a check. Deleting it leaves the
    // check ticked with nothing behind it, so say which one rather than letting
    // the fitter discover it afterwards.
    final proofFor = b.checklist
        .where((c) => c.proofUrl != null && c.proofUrl == photo.url)
        .map((c) => c.label).toList();

    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Remove this photo?', style: display(18, w: FontWeight.w600)),
      content: Text(
        proofFor.isEmpty
          ? 'Your project manager and the client can see this photo. '
            'Removing it cannot be undone.'
          : 'This photo is the proof for "${proofFor.first}". Removing it leaves '
            'that check ticked with nothing behind it, and your project manager '
            'will see that.',
        style: const TextStyle(fontSize: 13.5, height: 1.35, color: BT.mut)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false),
          child: const Text('Keep it', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Remove', style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700))),
      ],
    ));
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(workshopRepoProvider).deleteStagePhoto(photo.id!);
      ref.invalidate(stageBundleProvider(task.stageId));
      ref.invalidate(truckPhotosProvider(task.projectId));
      ref.invalidate(stagePhotosProvider(task.stageId));
      if (context.mounted) {
        Haptic.confirm();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Photo removed')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
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
      // `double.maxFinite`, not `double.infinity`, and the width is set here
      // rather than on the image.
      //
      // AlertDialog measures its body through an IntrinsicWidth, and
      // RenderIntrinsicWidth asserts `input.isFinite`. An `Image.memory` with
      // `width: double.infinity` reports an infinite intrinsic width, so the
      // assertion fired during layout — every frame, for as long as the dialog
      // was up. The route was pushed, so its barrier painted and dimmed the
      // screen, but the dialog itself never laid out and never appeared: pick a
      // photo and the app went dark and unresponsive with nothing on it. That
      // is the "it froze when I chose a photo from the library" report.
      //
      // The stretch is what makes the preview fill the dialog now; the image
      // only states its height.
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(photo.bytes, height: 150, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(height: 150, alignment: Alignment.center,
                color: BT.card2,
                child: const Icon(Icons.broken_image_outlined, size: 26, color: BT.mut2))),
          ),
          const SizedBox(height: 12),
          Container(decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(controller: noteC,
              decoration: const InputDecoration(hintText: 'Caption (optional)', border: InputBorder.none))),
        ]),
      ),
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


  /// Has the client approved a design that discharges this stage?
  ///
  /// Mirrors the server rule in 0028: a design linked to this stage if there
  /// is one, otherwise any approved design on the build — so a design made
  /// before the stage link existed still counts.
  bool _designApproved(WidgetRef ref) {
    final all = ref.watch(myDesignsProvider).valueOrNull;
    if (all == null) return true;   // unknown: do not accuse the designer
    final linked = all.where((d) => d.stageId == task.stageId).toList();
    final pool = linked.isNotEmpty ? linked : all.where((d) => d.projectId == task.projectId);
    return pool.any((d) => d.status == 'approved');
  }

  String _designHint(WidgetRef ref) {
    final all = ref.watch(myDesignsProvider).valueOrNull ?? const <DesignItem>[];
    final mine = all.where((d) => d.projectId == task.projectId).toList();
    if (mine.isEmpty) {
      return 'This stage finishes when the client approves a design for this '
             'build. Create one and submit it for their approval.';
    }
    if (mine.any((d) => d.status == 'pending_approval')) {
      return 'A design is with the client now. Once they approve it, you can '
             'submit this stage to your project manager.';
    }
    if (mine.any((d) => d.status == 'revision')) {
      return 'The client asked for changes. Upload a revised version and send '
             'it back — the stage can move once they approve one.';
    }
    return 'Your design is still a draft. Submit it for the client\'s approval '
           'first; this stage finishes when they sign off.';
  }

  /// Report why this stage is held up — reason, days, and a note the PM reads.
  Future<void> _logDelay(BuildContext context, WidgetRef ref) async {
    String reason = 'procurement';
    final daysC = TextEditingController(text: '1');
    final noteC = TextEditingController();

    final ok = await showAppSheet<bool>(context: context, builder: (sctx) =>
      StatefulBuilder(builder: (sctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report a hold-up', style: display(21, w: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Your project manager sees this against the stage, with the reason '
                     'attributed on the build.',
            style: TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
          const SizedBox(height: 16),
          const SectionLabel('What is holding it up'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in const [
              ('procurement', 'Parts not here'),
              ('design_approval', 'Waiting on design'),
              ('workshop_capacity', 'No capacity'),
              ('quality', 'Quality rework'),
              ('weather', 'Weather'),
              ('client', 'Waiting on client'),
              ('other', 'Something else'),
            ])
              AppChip(r.$2, selected: reason == r.$1,
                onTap: () => setLocal(() => reason = r.$1)),
          ]),
          const SizedBox(height: 16),
          LabelledField('DAYS LOST SO FAR', controller: daysC,
            hint: '1', keyboardType: TextInputType.number),
          const SizedBox(height: 11),
          LabelledField('ANYTHING YOUR PM SHOULD KNOW', controller: noteC, lines: 3,
            hint: 'The gas line fittings have not arrived from stores.'),
          const SizedBox(height: 18),
          PrimaryButton('Report it', icon: Icons.send_rounded,
            onTap: () => Navigator.pop(sctx, true)),
          const SizedBox(height: 6),
        ])));
    if (ok != true || !context.mounted) return;

    final days = int.tryParse(daysC.text.trim()) ?? 1;
    try {
      await ref.read(workshopRepoProvider).logStageDelay(task.stageId,
        reasonCode: reason, days: days < 0 ? 0 : days, note: noteC.text);
      ref.invalidate(stageBundleProvider(task.stageId));
      if (context.mounted) {
        Haptic.confirm();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Reported — your PM can see it on the build')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(workshopRepoProvider).startTask(task.stageId);
      Haptic.confirm();
      ref.invalidate(stageBundleProvider(task.stageId));
      // Stays on this screen. It used to pop straight back to the list, so a
      // designer who tapped Start on a stage that was ready to submit landed
      // in the Studio and had to find the stage again to submit it. The
      // button keeps spinning until the stage has reloaded, so it turns into
      // Submit rather than offering Start a second time.
      ref.invalidate(myTasksProvider);
      try {
        await ref.read(myTasksProvider.future);
      } catch (_) {
        // The stage did start; the list says so on its next load.
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Stage started — your PM has been told')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }

  Future<void> _submit(BuildContext context, WidgetRef ref, {int openChecks = 0}) async {
    if (openChecks > 0) {
      final go = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        backgroundColor: BT.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('$openChecks check${openChecks == 1 ? '' : 's'} still open',
          style: display(18, w: FontWeight.w600)),
        content: const Text('Your PM will see the checklist as it is. Submit anyway?',
          style: TextStyle(fontSize: 13.5, height: 1.35)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep working', style: TextStyle(color: BT.mut))),
          TextButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Submit anyway',
              style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
        ],
      ));
      if (go != true || !context.mounted) return;
    }
    try {
      await ref.read(workshopRepoProvider).submitForApproval(task.stageId);
      Haptic.confirm();
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


/// One stage photo: tap to open it full-screen, × to remove it.
///
/// A photo could be added and never taken back, so a fitter who uploaded the
/// wrong shot was stuck with it on the client's build timeline. [onDelete] is
/// null when nobody may remove it — an approved stage's photos are part of
/// what the PM signed off (0030).
class _PhotoThumb extends StatelessWidget {
  final StagePhoto photo;
  final VoidCallback? onDelete;
  const _PhotoThumb({required this.photo, this.onDelete});

  @override
  Widget build(BuildContext context) => SizedBox(width: 104, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        GestureDetector(
          onTap: () => openDocument(context,
            fileUrl: photo.url, title: photo.caption ?? 'Work photo'),
          child: ClipRRect(borderRadius: BorderRadius.circular(13),
            child: Image.network(photo.url, width: 104, height: 76, fit: BoxFit.cover,
              // A stage photo can be a dead URL (bucket cleared, bad upload). It
              // must leave a gap, not take the screen down.
              errorBuilder: (_, __, ___) => Container(width: 104, height: 76,
                alignment: Alignment.center, color: BT.card2,
                child: const Icon(Icons.broken_image_outlined, size: 20, color: BT.mut2)),
              loadingBuilder: (_, child, p) => p == null ? child
                : Container(width: 104, height: 76, color: BT.card2))),
        ),
        if (onDelete != null) Positioned(top: 4, right: 4, child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDelete,
          // Generous tap target around a small mark — this is pressed with a
          // work glove on.
          child: Padding(padding: const EdgeInsets.all(4), child: Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white))),
        )),
      ]),
      const SizedBox(height: 4),
      Text(photo.caption ?? 'Work photo', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: BT.mut)),
    ]),
  );
}

/// One checklist row — the tick, and since 0029 the record behind it.
///
/// Toggling is optimistic (the tick flips immediately, so a slow workshop
/// connection doesn't feel dead), guarded against a re-tap while the write is
/// in flight, and surfaces a failure instead of silently swallowing it.
///
/// What is new is that the tick is no longer a bare column write. It goes
/// through `fn_tick_check`, which records who ticked it and when, audits it,
/// refuses it once the PM has approved the stage, and refuses a
/// **photo-required** check with nothing to show. So this row has to be able
/// to say all of that: who ticked it, that it wants a photo, and which photo
/// discharged it.
class _ChecklistTile extends ConsumerStatefulWidget {
  final ChecklistItem c;
  final String stageId, projectId;
  /// The stage's photos — a photo-required check is discharged by picking one.
  final List<StagePhoto> photos;
  /// The stage is approved, or its truck has gone out: the checklist is the
  /// evidence as signed off and the server will refuse a change.
  final bool frozen;
  final bool divider;
  const _ChecklistTile({super.key, required this.c, required this.stageId,
    required this.projectId, required this.photos,
    this.frozen = false, this.divider = true});
  @override
  ConsumerState<_ChecklistTile> createState() => _ChecklistTileState();
}

class _ChecklistTileState extends ConsumerState<_ChecklistTile> {
  bool? _optimistic; // set while a toggle is pending / until the refetch agrees
  bool _busy = false;

  static final _fmt = DateFormat('d MMM');

  @override
  void didUpdateWidget(covariant _ChecklistTile old) {
    super.didUpdateWidget(old);
    // Server refetch landed with a new value — let it be the source of truth again.
    if (old.c.done != widget.c.done) _optimistic = null;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final c = widget.c;

    if (widget.frozen) {
      _say('This stage is signed off — its checklist is part of the approval.');
      return;
    }

    final target = !(_optimistic ?? c.done);

    // Ticking a check is where a photo belongs.
    //
    // Marking the work done and photographing it are the same moment, so the
    // camera is offered on **every** tick rather than only on the checks a PM
    // flagged — that is what makes "Add photo" up in the Photos section mean
    // "something extra", and it is why a check's photo lands in that list
    // automatically: it is an ordinary stage attachment, captioned with the
    // check it came from.
    //
    // Offered, not forced. Some checks have nothing to photograph — *client
    // sign-off received*, *keys handed over* — and demanding one anyway is how
    // a fitter learns to photograph the floor to get past the sheet. Once the
    // list fills with pictures of the floor the PM stops opening any of them,
    // and the checks where a photo genuinely mattered lose their reader too.
    // So there is a Skip, except on the checks the PM marked as needing one,
    // where the server would refuse the tick anyway.
    //
    // Un-ticking never asks.
    String? proof;
    if (target) {
      final choice = await _pickProof(required: c.photoRequired);
      if (choice == null) return;         // backed out — leave the check alone
      proof = choice.id;                  // null when they chose to skip
    }

    setState(() { _optimistic = target; _busy = true; });
    Haptic.tap();
    try {
      await ref.read(workshopRepoProvider)
          .toggleChecklist(c.id, target, proofAttachmentId: proof);
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

  void _say(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(backgroundColor: BT.ink, content: Text(msg)));

  /// Which photo goes with this check: one taken now, one already on the stage,
  /// or none.
  ///
  /// Returns null when the fitter backs out entirely — the check is then left
  /// alone. A record with a null `id` means "tick it, no photo", which only the
  /// un-required checks can offer.
  Future<({String? id})?> _pickProof({required bool required}) async {
    final existing = widget.photos;
    final choice = await showAppSheet<String>(
      context: context,
      // A required check cannot be ticked without a photo, so dismissing the
      // sheet by dragging it away would silently do nothing. Dismissal is a
      // real answer for the rest, and the Skip button is the obvious one.
      builder: (sctx) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(required ? 'This check needs a photo' : 'Add a photo?',
          style: display(20, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(required
            ? widget.c.label
            : '${widget.c.label} — your project manager and the client see '
              'these as the evidence of the work.',
          style: const TextStyle(fontSize: 13, color: BT.mut, height: 1.35)),
        const SizedBox(height: 16),
        PrimaryButton('Take a photo now', icon: Icons.photo_camera_rounded,
          onTap: () => Navigator.pop(sctx, '__new__')),
        if (existing.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('…or use one already on this stage'),
          SizedBox(height: 104, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: existing.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.pop(sctx, existing[i].id),
              child: _PhotoThumb(photo: existing[i])),
          )),
        ],
        if (!required) ...[
          const SizedBox(height: 14),
          SecondaryButton('Tick it without a photo', icon: Icons.check_rounded,
            onTap: () => Navigator.pop(sctx, '__skip__')),
        ],
        const SizedBox(height: 8),
      ]));
    if (choice == null || !mounted) return null;
    if (choice == '__skip__') return (id: null);

    // An existing photo hands back its own attachment id, which is what the
    // server records against the check.
    if (choice != '__new__') return (id: choice);

    final photo = await pickPhoto(context);
    // Backed out of the camera: fall back to the sheet's own question rather
    // than silently ticking or silently doing nothing.
    if (photo == null || !mounted) return null;
    final bar = ScaffoldMessenger.of(context);
    bar.showSnackBar(const SnackBar(backgroundColor: BT.ink,
      duration: Duration(minutes: 1), content: Row(children: [
        SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: BT.lime)),
        SizedBox(width: 12), Text('Uploading photo…'),
      ])));
    try {
      // An ordinary stage attachment, captioned with the check it came from —
      // which is what puts it in the Photos list automatically and tells the
      // PM which check it belongs to without anyone having to say so.
      final id = await ref.read(workshopRepoProvider).addStagePhoto(
        widget.stageId, photo.bytes,
        filename: photo.filename, contentType: photo.contentType,
        caption: widget.c.label);
      bar.clearSnackBars();
      ref.invalidate(truckPhotosProvider(widget.projectId));
      ref.invalidate(stagePhotosProvider(widget.stageId));
      return (id: id);
    } catch (e) {
      bar.clearSnackBars();
      bar.showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
      // The upload failed, so there is nothing to attach. The check is left
      // un-ticked rather than ticked with a photo that never arrived.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final done = _optimistic ?? c.done;
    // The tick is optimistic and instant: the box fills, the check pops in
    // with a small overshoot, and the label fades to struck-through, all
    // before the server answers.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: widget.divider ? const Border(bottom: BorderSide(color: BT.line)) : null),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: AnimatedContainer(
            duration: Motion.fast, curve: Motion.move,
            width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: done ? BT.lime : Colors.transparent, borderRadius: BorderRadius.circular(9),
              border: Border.all(color: done ? BT.lime : BT.mut2, width: 2)),
            child: AnimatedScale(
              scale: done ? 1 : 0,
              duration: done ? Motion.base : Motion.fast,
              curve: done ? Curves.easeOutBack : Motion.exit,
              child: const Icon(Icons.check_rounded, size: 15, color: BT.ink)))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: AnimatedDefaultTextStyle(
                duration: Motion.fast,
                // Start from the theme's body style so the app font is kept.
                // AnimatedDefaultTextStyle replaces the ambient style, it doesn't merge.
                style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(fontSize: 14.5,
                  color: done ? BT.mut2 : BT.ink,
                  decoration: done ? TextDecoration.lineThrough : TextDecoration.none, decorationColor: BT.mut2)),
                child: Text(c.label))),
              // Says what the check wants *before* it is tapped, so the rule
              // is never a surprise refusal.
              if (c.photoRequired && !done) ...[
                const SizedBox(width: 8),
                const Icon(Icons.photo_camera_outlined, size: 15, color: BT.mut2),
              ],
            ]),
            // Who ticked it, and when. The whole reason 0029 exists.
            //
            // Driven by the **server's** `c.done`, not the optimistic flag. The
            // tick flips instantly so a slow connection does not feel dead, but
            // the name and date only exist once the write has landed — reading
            // them off the optimistic state meant that the moment you ticked
            // anything it said "Ticked before this was recorded", which is
            // nonsense for a check you just ticked, and alarming nonsense at
            // that. While the write is in flight the row says so instead.
            if (_busy && (_optimistic ?? false) && !c.done) ...[
              const SizedBox(height: 3),
              const Text('Saving…',
                style: TextStyle(fontSize: 11.5, color: BT.mut2)),
            ] else if (c.done) ...[
              const SizedBox(height: 3),
              Row(children: [
                Flexible(child: Text(
                  c.doneByName == null
                    // Ticked before 0029 existed: the old write stored nothing,
                    // so there is no name to recover and none is invented.
                    ? (c.doneAt == null
                        ? 'Ticked earlier — before the app recorded who'
                        : 'Ticked ${_fmt.format(c.doneAt!)}')
                    : '${c.doneByName}'
                      '${c.doneAt == null ? '' : ' · ${_fmt.format(c.doneAt!)}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: BT.mut2))),
                if (c.proofUrl != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => openDocument(context, fileUrl: c.proofUrl, title: c.label),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.image_outlined, size: 13, color: BT.ink),
                      SizedBox(width: 3),
                      Text('Proof', style: TextStyle(fontSize: 11.5,
                        fontWeight: FontWeight.w700, color: BT.ink)),
                    ])),
                ]
                // Ticked, wants a photo, has none — only possible on a row
                // ticked before the rule was added. Better said than shown as
                // a tick that quietly means less than the one above it.
                else if (c.proofMissing) ...[
                  const SizedBox(width: 8),
                  const Text('No photo on record', style: TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w600, color: BT.coral)),
                ],
              ]),
            ],
          ])),
        ]),
      ),
    );
  }
}

/// The supervisor's breakdown of a workshop stage into work for individual
/// people (0033).
///
/// Read-only for everyone but the person the stage was handed to — and for a
/// worker looking at a stage that is not theirs, this is simply the picture of
/// who is doing what, which is worth seeing.
class _SubStages extends ConsumerWidget {
  final WorkshopTask task;
  final bool frozen;
  const _SubStages({required this.task, required this.frozen});

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stageTasksProvider(task.stageId));
    // Only the person holding the stage plans it. This screen is reached from
    // "my stages" — myTasks() returns only stages assigned to the signed-in
    // person — so the viewer *is* that person. The server says the same thing
    // (trg_guard_stage_tasks); this is only so the screen never offers an edit
    // that would be refused.
    final canPlan = !frozen;

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: ErrorCard('Could not load the work items.\n${friendlyError(e)}',
          onRetry: () => ref.invalidate(stageTasksProvider(task.stageId))),
      ),
      data: (tasks) {
        if (tasks.isEmpty && !canPlan) return const SizedBox.shrink();
        final locked = lockedTaskIds(tasks);
        final done = tasks.where((t) => t.isDone).length;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            child: Row(children: [
              Expanded(child: Text(
                tasks.isEmpty ? 'WORK ITEMS' : 'WORK ITEMS · $done/${tasks.length}',
                style: const TextStyle(fontSize: 11, letterSpacing: 1.2,
                  color: BT.mut, fontWeight: FontWeight.w600))),
              if (canPlan)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _add(context, ref, tasks),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_rounded, size: 15, color: BT.ink),
                      SizedBox(width: 3),
                      Text('Add item', style: TextStyle(fontSize: 12.5,
                        fontWeight: FontWeight.w700, color: BT.ink)),
                    ])),
                ),
            ]),
          ),
          if (tasks.isEmpty)
            EmptyState(icon: Icons.checklist_rtl_rounded, tint: BT.card2,
              title: 'Nothing broken down yet',
              subtitle: canPlan
                ? 'Split this stage into the jobs it actually is, and give each '
                  'one to somebody. They will see it in their own list.'
                : 'The supervisor has not split this stage up yet.')
          else
            AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (var i = 0; i < tasks.length; i++)
                  _row(context, ref, tasks[i], tasks,
                    locked: locked.contains(tasks[i].id),
                    sharesWithAbove: i > 0 && tasks[i].step == tasks[i - 1].step,
                    canPlan: canPlan,
                    divider: i < tasks.length - 1),
              ])),
          if (canPlan && tasks.isNotEmpty)
            const Padding(padding: EdgeInsets.only(top: 9, left: 4),
              child: Text('Tap an item to give it to someone, or to say it runs '
                          'alongside the one above.',
                style: TextStyle(fontSize: 12, color: BT.mut, height: 1.3))),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, StageTask t, List<StageTask> all, {
    required bool locked, required bool sharesWithAbove,
    required bool canPlan, required bool divider,
  }) {
    final mine = sb.auth.currentUser?.id;
    final isMine = t.assigneeId != null && t.assigneeId == mine;
    final tone = t.isDone
        ? (label: 'Done', color: BT.lime)
        : locked
            ? (label: 'Waiting', color: BT.card2)
            : t.isActive
                ? (label: 'In progress', color: BT.amber)
                : (label: 'To do', color: BT.sky);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: divider
          ? const Border(bottom: BorderSide(color: BT.line)) : null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canPlan ? () => _edit(context, ref, t, all) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Items that run together are drawn as one group, so the shape of
          // the plan is visible without reading step numbers.
          SizedBox(width: 16, child: Column(children: [
            Icon(sharesWithAbove ? Icons.subdirectory_arrow_right_rounded
                                 : Icons.circle,
              size: sharesWithAbove ? 14 : 7,
              color: sharesWithAbove ? BT.mut2 : (t.isDone ? BT.lime : BT.mut2)),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: t.isDone ? BT.mut2 : BT.ink,
                decoration: t.isDone ? TextDecoration.lineThrough : null,
                decorationColor: BT.mut2)),
            const SizedBox(height: 3),
            Text([
              if (t.assigneeName != null) t.assigneeName! else 'Nobody yet',
              if (t.isDone && t.doneAt != null) _fmt.format(t.doneAt!),
            ].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5,
                color: t.isUnassigned && !t.isDone ? BT.coral : BT.mut2)),
          ])),
          const SizedBox(width: 8),
          // The person it belongs to moves it from here; everyone else reads it.
          if (isMine && !frozen && !locked && !t.isDone)
            StageTaskMoveButton(task: t, stageId: task.stageId)
          else
            StatusPill(tone.label, color: tone.color),
        ]),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<StageTask> existing) async {
    final c = TextEditingController();
    final ok = await showAppSheet<bool>(context: context, builder: (sctx) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add a work item', style: display(20, w: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('One job, for one person. You can give it to somebody after.',
          style: TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
        const SizedBox(height: 16),
        LabelledField('WHAT NEEDS DOING', controller: c,
          hint: 'Hole drilling for electrical work'),
        const SizedBox(height: 18),
        PrimaryButton('Add', icon: Icons.add_rounded,
          onTap: () => Navigator.pop(sctx, true)),
        const SizedBox(height: 6),
      ]));
    if (ok != true || !context.mounted || c.text.trim().isEmpty) return;

    // New items go at the end, in their own step — the supervisor groups them
    // afterwards if they run alongside something.
    final nextOrd = existing.isEmpty
        ? 1 : existing.map((t) => t.ord).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await ref.read(workshopRepoProvider)
          .addStageTask(task.stageId, c.text, ord: nextOrd, step: nextOrd);
      ref.invalidate(stageTasksProvider(task.stageId));
      ref.invalidate(myStageTasksProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, StageTask t, List<StageTask> all) async {
    final idx = all.indexOf(t);
    final above = idx > 0 ? all[idx - 1] : null;
    var runsWithAbove = above != null && t.step == above.step;

    await showAppSheet<void>(context: context, builder: (sctx) =>
      StatefulBuilder(builder: (sctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title, style: display(19, w: FontWeight.w600)),
          const SizedBox(height: 14),
          const SectionLabel('Who is doing it'),
          _AssigneePicker(
            current: t.assigneeId,
            onPick: (uid) async {
              await ref.read(workshopRepoProvider).assignStageTask(t.id, uid);
              ref.invalidate(stageTasksProvider(task.stageId));
              // "My work items" is somebody's whole list — the supervisor's
              // own, when they give an item to themselves. It must not wait
              // for a re-login to show up.
              ref.invalidate(myStageTasksProvider);
              if (sctx.mounted) Navigator.pop(sctx);
            }),
          if (above != null) ...[
            const SizedBox(height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final next = !runsWithAbove;
                setLocal(() => runsWithAbove = next);
                // Joining the step above, or taking its own back.
                await ref.read(workshopRepoProvider)
                    .setStageTaskStep(t.id, next ? above.step : t.ord);
                ref.invalidate(stageTasksProvider(task.stageId));
                // What is waiting on what changed, and the worker's list shows it.
                ref.invalidate(myStageTasksProvider);
              },
              child: Row(children: [
                Icon(runsWithAbove
                    ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 20, color: runsWithAbove ? BT.ink : BT.mut2),
                const SizedBox(width: 10),
                Expanded(child: Text('Runs alongside "${above.title}"',
                  maxLines: 2,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
              ]),
            ),
            const Padding(padding: EdgeInsets.only(top: 6, left: 30),
              child: Text('Off, it waits for the one above to be finished.',
                style: TextStyle(fontSize: 11.5, color: BT.mut2))),
          ],
          const SizedBox(height: 20),
          SecondaryButton('Remove this item', icon: Icons.delete_outline_rounded,
            onTap: () async {
              await ref.read(workshopRepoProvider).removeStageTask(t.id);
              ref.invalidate(stageTasksProvider(task.stageId));
              ref.invalidate(myStageTasksProvider);
              if (sctx.mounted) Navigator.pop(sctx);
            }),
          const SizedBox(height: 6),
        ])));
  }
}

/// Start / finish, for the person a work item belongs to.
///
/// Public because the same button is the whole interaction on two screens: the
/// stage's breakdown, and the worker's own list of items on the Tasks tab.
class StageTaskMoveButton extends ConsumerStatefulWidget {
  final StageTask task;
  final String stageId;
  const StageTaskMoveButton({super.key, required this.task, required this.stageId});
  @override
  ConsumerState<StageTaskMoveButton> createState() => StageTaskMoveButtonState();
}

class StageTaskMoveButtonState extends ConsumerState<StageTaskMoveButton> {
  bool _busy = false;

  Future<void> _move(String to) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(workshopRepoProvider).setStageTaskStatus(widget.task.id, to);
      ref.invalidate(stageTasksProvider(widget.stageId));
      ref.invalidate(myStageTasksProvider);
      Haptic.confirm();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: SizedBox(width: 15, height: 15,
          child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut2)));
    }
    final next = widget.task.isActive ? 'done' : 'in_progress';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _move(next),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: widget.task.isActive ? BT.ink : BT.card2,
          borderRadius: BorderRadius.circular(999),
          border: widget.task.isActive ? null : Border.all(color: BT.line)),
        child: Text(widget.task.isActive ? 'Finish' : 'Start',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: widget.task.isActive ? Colors.white : BT.ink)),
      ),
    );
  }
}

/// The workshop people a job can be given to.
class _AssigneePicker extends ConsumerWidget {
  final String? current;
  final ValueChanged<String?> onPick;
  const _AssigneePicker({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    return members.when(
      loading: () => const SkeletonList(count: 2),
      error: (e, _) => ErrorCard('Could not load the team.\n${friendlyError(e)}'),
      data: (list) {
        final workshop = list
            .where((m) => m.role == 'workshop' && m.status == 'active')
            .toList();
        return Column(children: [
          for (final m in workshop)
            Padding(padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => onPick(m.id),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(current == m.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                    size: 18, color: current == m.id ? BT.ink : BT.mut2),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name.isEmpty ? m.email : m.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (m.subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(m.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: BT.mut2)),
                      ],
                    ])),
                ]))),
          if (current != null)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: SecondaryButton('Give it back to nobody',
                icon: Icons.person_off_outlined, onTap: () => onPick(null))),
        ]);
      },
    );
  }
}

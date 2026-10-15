import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
                projectId: task.projectId,
                photos: b.photos, frozen: task.isClosed,
                divider: i < b.checklist.length - 1),
          ])),
      // A check that wants a photo and has not got one is the fitter's own cue,
      // said once under the list rather than shouted on every row.
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

      // what this stage is meant to be built from
      if (b.materials.isNotEmpty) ...[
        const SectionLabel('Parts this stage needs'),
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

      // actions
      const SizedBox(height: 16),
      if (!task.isClosed) Row(children: [
        // "Photo" means a site photo — a workshop idea. A designer attaching
        // one is attaching a reference, so the button says what it does for
        // whoever is reading it.
        Expanded(child: SecondaryButton(showInstallPart ? 'Photo' : 'Reference',
          icon: Icons.photo_camera_outlined, onTap: () => _addPhoto(context, ref))),
        if (showInstallPart) ...[
          const SizedBox(width: 11),
          Expanded(child: SecondaryButton('Install part', icon: Icons.qr_code_scanner_rounded, onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanInstall(task: task))))),
        ],
      ]),
      // Report a slip against your own stage.
      //
      // `delay_logs` has always granted the workshop role write, and the fitter
      // is the one who knows the steel did not arrive — but no screen ever
      // offered it, so the PM had to notice the stage was late and then guess.
      // 0029 narrowed the grant to the stage's own assignee, which is what made
      // it safe to put here.
      if (!task.isClosed && !task.canStart) ...[
        const SizedBox(height: 11),
        SecondaryButton('Report a hold-up', icon: Icons.schedule_rounded,
          onTap: () => _logDelay(context, ref)),
      ],
      const SizedBox(height: 11),
      if (task.isDelivered)
        // The truck has gone out. fn_mark_delivered(force) leaves open stages
        // open deliberately — closing them would rewrite what happened — but
        // offering Start work on a customer's truck is not a live action.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(color: BT.card2,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.local_shipping_outlined, size: 19, color: BT.mut),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('This truck has been delivered',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              const Text('The build was closed with this stage still open. It is kept '
                         'as a record — talk to your project manager if work is still needed.',
                style: TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
            ])),
          ]),
        )
      else if (task.awaitingApproval)
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
      else if (designGate && !_designApproved(ref)) ...[
        // Not a disabled button: a button that does nothing explains nothing.
        // This states the one thing standing in the way and who it is with.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(color: BT.card2,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.palette_outlined, size: 19, color: BT.mut),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Waiting on the client',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(_designHint(ref),
                style: const TextStyle(fontSize: 12.5, color: BT.mut, height: 1.35)),
            ])),
          ]),
        ),
      ]
      else
        AsyncPrimaryButton(allDone || total == 0 ? 'Submit for approval' : 'Submit with checks open',
          icon: Icons.check_rounded, bg: BT.ink, fg: Colors.white,
          // With checks still open the button used to read "Mark stage
          // complete" and submit regardless — the PM then got a submission
          // whose own checklist said it wasn't finished. It still goes through
          // (sometimes a check genuinely doesn't apply), but deliberately.
          onTap: () => _submit(context, ref, openChecks: total - done)),
      if (!task.isDelivered && !task.awaitingApproval && !task.canStart && !allDone && total > 0)
        Padding(padding: const EdgeInsets.only(top: 10),
          // Full width so textAlign.center actually centres it (it sat left).
          child: SizedBox(width: double.infinity, child: Text('$done of $total checks done — finish all before final approval.',
            textAlign: TextAlign.center, style: const TextStyle(color: BT.mut, fontSize: 12)))),

      // The photos on this stage.
      //
      // The bundle has always fetched these and the screen never drew them —
      // so the person who took the photo could not see it, could not tell what
      // had already gone up, and could not check the right thing was in frame.
      // The client sees them; the fitter could not.
      if (b.photos.isNotEmpty) ...[
        SectionLabel('Photos · ${b.photos.length}'),
        SizedBox(height: 104, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: b.photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _PhotoThumb(photo: b.photos[i]),
        )),
        const SizedBox(height: 4),
      ],

      // Why this stage slipped — also fetched and never shown.
      if (b.delays.isNotEmpty) ...[
        const SectionLabel('Delays logged'),
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
              ]))),
      ],

      // The whole truck's record, for the person building it.
      //
      // `v_truck_components` has carried every part, its serial, its stage and
      // who fitted it since 0023 — and the screen that shows it lived only
      // inside the build screen, which Admin and the PM can open and Workshop
      // cannot. The fitter had no way to see the record they were writing.
      if (showInstallPart) ...[
        const SizedBox(height: 18),
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
          child: Image.memory(photo.bytes, height: 150, width: double.infinity, fit: BoxFit.cover,
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


/// One stage photo, tappable to open full-screen.
class _PhotoThumb extends StatelessWidget {
  final StagePhoto photo;
  const _PhotoThumb({required this.photo});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => openDocument(context, fileUrl: photo.url, title: photo.caption ?? 'Work photo'),
    child: SizedBox(width: 104, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(13),
          child: Image.network(photo.url, width: 104, height: 76, fit: BoxFit.cover,
            // A stage photo can be a dead URL (bucket cleared, bad upload). It
            // must leave a gap, not take the screen down.
            errorBuilder: (_, __, ___) => Container(width: 104, height: 76,
              alignment: Alignment.center, color: BT.card2,
              child: const Icon(Icons.broken_image_outlined, size: 20, color: BT.mut2)),
            loadingBuilder: (_, child, p) => p == null ? child
              : Container(width: 104, height: 76, color: BT.card2))),
        const SizedBox(height: 4),
        Text(photo.caption ?? 'Work photo', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: BT.mut)),
      ])),
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

    // A check that asks for a photo needs one named before it can be ticked.
    // The server refuses it either way; asking here means the fitter gets a
    // picker instead of an error.
    String? proof;
    if (target && c.photoRequired) {
      proof = await _pickProof();
      if (proof == null) return;    // cancelled, or nothing to point at yet
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

  /// Which photo proves this check. Either one already on the stage, or a new
  /// one taken now — the common case on a floor is "take it, then tick it".
  Future<String?> _pickProof() async {
    final existing = widget.photos;
    final choice = await showAppSheet<String>(context: context, builder: (sctx) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This check needs a photo', style: display(20, w: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(widget.c.label,
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
        const SizedBox(height: 8),
      ]));
    if (choice == null || !mounted) return null;

    // An existing photo hands back its own attachment id, which is what the
    // server records against the check.
    if (choice != '__new__') return choice;

    final photo = await pickPhoto(context);
    if (photo == null || !mounted) return null;
    final bar = ScaffoldMessenger.of(context);
    bar.showSnackBar(const SnackBar(backgroundColor: BT.ink,
      duration: Duration(minutes: 1), content: Row(children: [
        SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: BT.lime)),
        SizedBox(width: 12), Text('Uploading proof…'),
      ])));
    try {
      final id = await ref.read(workshopRepoProvider).addStagePhoto(
        widget.stageId, photo.bytes,
        filename: photo.filename, contentType: photo.contentType,
        caption: widget.c.label);
      bar.clearSnackBars();
      ref.invalidate(truckPhotosProvider(widget.projectId));
      ref.invalidate(stagePhotosProvider(widget.stageId));
      return id;
    } catch (e) {
      bar.clearSnackBars();
      bar.showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
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
            if (done) ...[
              const SizedBox(height: 3),
              Row(children: [
                Flexible(child: Text(
                  c.doneByName == null
                    ? (c.doneAt == null
                        ? 'Ticked before this was recorded'
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

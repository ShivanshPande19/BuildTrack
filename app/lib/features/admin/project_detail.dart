import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'stage_detail.dart';
import 'project_requirements.dart';
import '../client/truck_3d.dart';

/// Admin / PM — Project detail (a4): progress, delivery date, who owns the build,
/// and the build-stage timeline.
///
/// Role split: Admin owns *who runs the build* (the PM). The PM owns *who does
/// each stage*. Both are enforced in the database, not just here.
class ProjectDetailScreen extends ConsumerWidget {
  final String projectId;
  final Project? initial; // for an instant header while stages load
  final bool materialsEditable; // PM opens editable; Admin monitors (read-only)
  final bool canAssign;         // PM can assign stages to team members
  final bool canEditTimeline;   // PM can change delivery date (re-schedules)
  final bool canAssignPm;       // Admin can assign / change the project manager
  const ProjectDetailScreen({super.key, required this.projectId, this.initial,
    this.materialsEditable = false, this.canAssign = false, this.canEditTimeline = false,
    this.canAssignPm = false});

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
              error: (e, _) => AppCard(child: Text('Could not load project.\n${friendlyError(e)}',
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
    // id → name for showing stage assignees + the PM
    final names = <String, String>{
      for (final m in (ref.watch(membersProvider).valueOrNull ?? <Member>[])) m.id: m.name
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // title + status
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(d.project.name, style: display(27, w: FontWeight.w600))),
        const SizedBox(width: 10),
        StatusPill(s.label, color: s.color),
      ]),
      const SizedBox(height: 16),

      _pmCard(context, ref, d, names),
      const SizedBox(height: 12),

      // 3D design preview — shared by Admin + PM. Real approved model when
      // available, else the demo model.
      Truck3DPreview(
        glbUrl: ref.watch(truckModelUrlProvider(projectId)).valueOrNull ?? kDemoTruckGlb,
        label: d.project.name, height: 200),
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: !canEditTimeline ? null : () async {
                final picked = await showDatePicker(context: context,
                  initialDate: d.targetDelivery ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 730)));
                if (picked != null) {
                  await ref.read(projectsRepoProvider).setDeliveryDate(projectId, picked);
                  ref.invalidate(projectDetailProvider(projectId));
                  ref.invalidate(myProjectsProvider);
                  ref.invalidate(fleetProvider);
                }
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Delivery', style: TextStyle(color: BT.mut, fontSize: 11.5)),
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_d(d.targetDelivery), style: display(16, w: FontWeight.w600)),
                  if (canEditTimeline) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.edit_calendar_rounded, size: 15, color: BT.mut),
                  ],
                ]),
              ]),
            ),
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
      // Tag why a build slipped, and optionally push the delivery date by the
      // same number of days (which re-runs backward scheduling — the cascade).
      if (canEditTimeline && d.project.status != 'delivered' && d.stages.isNotEmpty) ...[
        const SizedBox(height: 12),
        _delayCard(context, ref, d),
      ],

      // Handover — the step that moves a build into after-sales. Until this
      // happens the Service role has nothing to support.
      if (canEditTimeline && d.project.status != 'delivered') ...[
        const SizedBox(height: 12),
        _deliverCard(context, ref, d),
      ],

      // Documents the client sees on their truck (contract, invoice, warranty
      // pack, handover certificate). Nothing created these before, so the
      // client's Documents tab was always empty.
      const SectionLabel('Documents'),
      _documentsCard(context, ref),

      const SectionLabel('Build stages'),
      if (d.stages.isEmpty)
        const EmptyState(
          icon: Icons.timeline_rounded, tint: BT.amber,
          title: 'No stages yet',
          subtitle: 'Stages generate from the workflow template when the project is onboarded.')
      else
        ...List.generate(d.stages.length,
          (i) => _timelineTile(context, ref, d.stages[i], i == d.stages.length - 1,
                               d.project, names)),
    ]);
  }

  /// Who runs this build. Admin-only control — and the loudest thing on the
  /// screen when it is missing, because nothing downstream can happen without it.
  Widget _pmCard(BuildContext context, WidgetRef ref, ProjectDetailData d, Map<String, String> names) {
    final pmId = d.project.pmId;
    final pmName = pmId == null ? null : (names[pmId] ?? 'Assigned');
    final missing = pmId == null;

    Future<void> pick() async {
      final chosen = await showModalBottomSheet<OptRef>(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => _PickPmSheet(currentPmId: pmId),
      );
      if (chosen == null) return;
      try {
        await ref.read(adminRepoProvider).assignPm(projectId, chosen.id);
        ref.invalidate(projectDetailProvider(projectId));
        ref.invalidate(fleetProvider);
        ref.invalidate(myProjectsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.ink,
            content: Text('${d.project.code} assigned to ${chosen.label}')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.coral, content: Text(friendlyError(e))));
        }
      }
    }

    return AppCard(
      color: missing ? const Color(0xFFFBE4E0) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: missing ? BT.coral : BT.sky, borderRadius: BorderRadius.circular(12)),
            child: Icon(missing ? Icons.person_off_rounded : Icons.engineering_rounded,
              size: 20, color: BT.ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Project manager', style: TextStyle(color: BT.mut, fontSize: 11.5)),
            const SizedBox(height: 2),
            Text(pmName ?? 'Not assigned',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5,
                color: missing ? BT.coral : BT.ink)),
          ])),
          if (canAssignPm) GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: pick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(999)),
              child: Text(missing ? 'Assign' : 'Change',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ]),
        if (missing) ...[
          const SizedBox(height: 10),
          Text(
            canAssignPm
              ? 'Until a PM owns this build, its stages cannot be assigned and no '
                'submitted work can be approved. Assign one to unblock it.'
              : 'This build has no project manager yet, so its stages cannot be '
                'assigned. Ask an admin to assign one.',
            style: const TextStyle(fontSize: 12, color: BT.ink, height: 1.4)),
        ],
      ]),
    );
  }

  /// Tag why the build slipped (against the stage that's slipping) and, if asked,
  /// push the delivery date by the same number of days — which re-runs backward
  /// scheduling, so every stage's plan moves with it.
  Widget _delayCard(BuildContext context, WidgetRef ref, ProjectDetailData d) {
    // The stage that is actually slipping: the first one not yet done.
    final current = d.stages.firstWhere((s) => s.status != 'done', orElse: () => d.stages.last);

    Future<void> open() async {
      final res = await showModalBottomSheet<_DelayResult>(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => _LogDelaySheet(stageName: current.name),
      );
      if (res == null) return;
      try {
        final repo = ref.read(projectsRepoProvider);
        await repo.logDelay(stageId: current.id, reasonCode: res.reason,
          daysDelayed: res.days, note: res.note);
        if (res.pushDelivery && res.days > 0) {
          final base = d.targetDelivery ?? DateTime.now();
          await repo.setDeliveryDate(projectId, base.add(Duration(days: res.days)));
        }
        ref.invalidate(projectDetailProvider(projectId));
        ref.invalidate(myProjectsProvider);
        ref.invalidate(fleetProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.ink,
            content: Text(res.pushDelivery && res.days > 0
              ? 'Delay logged · delivery pushed ${res.days} day${res.days == 1 ? '' : 's'}'
              : 'Delay logged on ${current.name}')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.coral, content: Text(friendlyError(e))));
        }
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: open,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.amber, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.timelapse_rounded, size: 20, color: Color(0xFF4A3410))),
          const SizedBox(width: 13),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Log a delay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            SizedBox(height: 2),
            Text('Tag the reason and reschedule', style: TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
        ]),
      ),
    );
  }

  /// Staff manage the client's documents here: what's attached, and an upload
  /// that makes a document available on the client's truck.
  Widget _documentsCard(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(projectDocsProvider(projectId));

    Future<void> add() async {
      final type = await showModalBottomSheet<String>(
        context: context, backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
            Text('Document type', style: display(19, w: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final e in _docTypeLabels.entries)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(ctx, e.key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
                  child: Row(children: [
                    const Icon(Icons.description_outlined, size: 19, color: BT.ink),
                    const SizedBox(width: 12),
                    Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  ]),
                ),
              ),
          ]),
        ),
      );
      if (type == null) return;
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: BT.coral, content: Text('Could not read that file.')));
        }
        return;
      }
      try {
        await ref.read(projectsRepoProvider).addDocument(
          projectId: projectId, type: type, bytes: bytes,
          filename: f.name, contentType: _docContentType(f.name));
        ref.invalidate(projectDocsProvider(projectId));
        ref.invalidate(truckDocsProvider(projectId));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.ink,
            content: Text('${_docTypeLabels[type]} added — the client can see it now')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.coral, content: Text(friendlyError(e))));
        }
      }
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        docsAsync.when(
          loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut)))),
          error: (e, _) => Text('Could not load documents.\n${friendlyError(e)}',
            style: const TextStyle(color: BT.coral, fontSize: 12)),
          data: (docs) => docs.isEmpty
            ? const Padding(padding: EdgeInsets.only(bottom: 4),
                child: Text('No documents yet. Add the contract, invoices, warranty pack or '
                            'handover certificate for the client.',
                  style: TextStyle(color: BT.mut, fontSize: 12.5, height: 1.35)))
            : Column(children: [
                for (final doc in docs) Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(children: [
                    const Icon(Icons.description_rounded, size: 18, color: BT.mut),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_docTypeLabels[doc.type] ?? doc.type,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                    StatusPill(doc.available ? 'Shared' : 'Hidden',
                      color: doc.available ? BT.lime : BT.mut2),
                  ]),
                ),
              ]),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: add,
          child: Container(height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.upload_file_rounded, size: 18, color: BT.ink), SizedBox(width: 8),
              Text('Add document', style: TextStyle(fontWeight: FontWeight.w600)),
            ])),
        ),
      ]),
    );
  }

  /// PM marks the truck handed over → it becomes 'delivered' and the Service
  /// role starts supporting it. Offers a confirm-anyway path when stages remain.
  Widget _deliverCard(BuildContext context, WidgetRef ref, ProjectDetailData d) {
    final pending = d.stages.where((s) => s.status != 'done').length;

    Future<void> deliver({required bool force}) async {
      try {
        await ref.read(projectsRepoProvider).markDelivered(projectId, force: force);
        ref.invalidate(projectDetailProvider(projectId));
        ref.invalidate(myProjectsProvider);
        ref.invalidate(fleetProvider);
        ref.invalidate(deliveredTrucksProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.ink,
            content: Text('${d.project.code} delivered — now in after-sales support')));
        }
      } catch (e) {
        if (!context.mounted) return;
        // The server refuses while stages are open; offer the explicit override.
        if (!force && pending > 0) {
          final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
            backgroundColor: BT.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text('Deliver anyway?', style: display(18, w: FontWeight.w600)),
            content: Text('$pending stage${pending == 1 ? '' : 's'} '
                          '${pending == 1 ? 'is' : 'are'} still not approved as done.',
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel', style: TextStyle(color: BT.mut))),
              TextButton(onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Deliver', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
            ],
          ));
          if (ok == true) await deliver(force: true);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral, content: Text(friendlyError(e))));
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => deliver(force: false),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.mint, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.local_shipping_rounded, size: 20, color: BT.ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mark delivered',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(pending == 0
                ? 'All stages approved — hand it over to the client'
                : '$pending stage${pending == 1 ? '' : 's'} still open',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
        ]),
      ),
    );
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

  Widget _timelineTile(BuildContext context, WidgetRef ref, Stage s, bool isLast,
      Project project, Map<String, String> names) {
    final done = s.status == 'done';
    final now = s.status == 'in_progress';
    final todo = s.status == 'todo';
    final rework = s.status == 'rework';

    final assignee = s.assigneeId == null ? null : names[s.assigneeId];
    final who = assignee ?? 'Unassigned';
    final subtitle = switch (s.status) {
      'done'        => 'Completed ${_d(s.actualEnd ?? s.plannedEnd)}${assignee != null ? ' · $assignee' : ''}',
      'in_progress' => 'In progress · $who',
      'rework'      => 'Sent back for rework · $who',
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
    } else if (rework) {
      dot = Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.coral, shape: BoxShape.circle),
        child: const Icon(Icons.replay_rounded, size: 13, color: BT.ink));
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
          Row(children: [
            Expanded(child: Text(s.name, style: TextStyle(fontSize: 15,
              fontWeight: todo ? FontWeight.w500 : FontWeight.w600,
              color: todo ? BT.mut2 : BT.ink))),
            if (s.discipline != null) _disciplineChip(s.discipline!),
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: BT.mut)),
          if (s.assignedDue != null && !done) ...[
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.flag_rounded, size: 12,
                color: s.assignedDue!.isBefore(DateTime.now()) ? BT.coral : BT.mut2),
              const SizedBox(width: 4),
              Text('Due ${_d(s.assignedDue)}',
                style: TextStyle(fontSize: 11,
                  color: s.assignedDue!.isBefore(DateTime.now()) ? BT.coral : BT.mut,
                  fontWeight: FontWeight.w600)),
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StageDetailScreen(stage: s, projectCode: project.code))),
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
                onTap: () => openAssignSheet(context, ref, s, projectId,
                  onDone: () {
                    ref.invalidate(projectDetailProvider(projectId));
                    ref.invalidate(workloadProvider);
                    ref.invalidate(stagesToAssignProvider);
                  }),
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
}

/// Small role tag on a stage, so it is obvious at a glance whose work it is.
Widget _disciplineChip(String discipline) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(color: roleColor(discipline).withOpacity(0.45),
    borderRadius: BorderRadius.circular(999)),
  child: Text(discipline,
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: BT.ink)),
);

/// Assign / reassign / unassign a stage (PM only). Shared by Project detail and
/// the PM's Assign work screen.
void openAssignSheet(BuildContext context, WidgetRef ref, Stage stage, String projectId,
    {VoidCallback? onDone}) {
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _AssignSheet(stage: stage, projectId: projectId, onDone: onDone),
  );
}

class _AssignSheet extends ConsumerStatefulWidget {
  final Stage stage;
  final String projectId;
  final VoidCallback? onDone;
  const _AssignSheet({required this.stage, required this.projectId, this.onDone});
  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  static final _fmt = DateFormat('d MMM');
  DateTime? _start, _due;
  bool _busy = false;
  String? _error;
  /// Set once the PM has confirmed handing this stage to another discipline.
  String? _overrideFor;

  @override
  void initState() {
    super.initState();
    _start = widget.stage.assignedStart ?? widget.stage.plannedStart;
    _due = widget.stage.assignedDue ?? widget.stage.plannedEnd;
  }

  Future<void> _apply(String? uid, {bool override = false}) async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(projectsRepoProvider).assignStage(
        widget.stage.id, uid, start: _start, due: _due, override: override);
      widget.onDone?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tapping someone outside the stage's discipline asks first, then overrides.
  Future<void> _tap(Member m) async {
    final disc = widget.stage.discipline;
    final mismatch = disc != null && m.role != disc;
    if (!mismatch || _overrideFor == m.id) {
      await _apply(m.id, override: mismatch);
      return;
    }
    setState(() {
      _overrideFor = m.id;
      _error = 'This is a $disc stage and ${m.name.isEmpty ? m.email : m.name} '
               'works in ${m.role}. Tap again to move the stage to ${m.role}.';
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final base = isStart ? _start : _due;
    final picked = await showDatePicker(
      context: context,
      initialDate: base ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 730)));
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_due != null && _due!.isBefore(picked)) _due = picked;
      } else {
        _due = picked;
      }
    });
  }

  Widget _dateChip(String label, DateTime? value, bool isStart) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickDate(isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BT.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: BT.mut, fontSize: 11)),
          const SizedBox(height: 3),
          Row(children: [
            Text(value == null ? 'Pick' : _fmt.format(value),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5,
                color: value == null ? BT.mut2 : BT.ink)),
            const Spacer(),
            const Icon(Icons.calendar_today_rounded, size: 14, color: BT.mut2),
          ]),
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(assignableForDisciplineProvider(widget.stage.discipline));
    final disc = widget.stage.discipline;

    return Container(
      decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Row(children: [
            Expanded(child: Text('Assign · ${widget.stage.name}', style: display(19, w: FontWeight.w600))),
            if (disc != null) _disciplineChip(disc),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _dateChip('Start', _start, true),
            const SizedBox(width: 10),
            _dateChip('Due', _due, false),
          ]),
          const SizedBox(height: 14),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: BT.coral),
                const SizedBox(width: 7),
                Expanded(child: Text(_error!,
                  style: const TextStyle(color: BT.ink, fontSize: 12.5, height: 1.35))),
              ]),
            )),
          if (_busy)
            const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: BT.ink)))
          else members.when(
            loading: () => const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => Text('Could not load team.\n${friendlyError(e)}',
              style: const TextStyle(color: BT.coral, fontSize: 13)),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(icon: Icons.people_outline_rounded, tint: BT.lav,
                  title: 'No assignable staff',
                  subtitle: 'Add workshop / design / store / service members first.');
              }
              final recommended = disc == null ? <Member>[] : list.where((m) => m.role == disc).toList();
              final others = disc == null ? list : list.where((m) => m.role != disc).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (recommended.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('RECOMMENDED · ${disc!.toUpperCase()}',
                      style: const TextStyle(fontSize: 10.5, letterSpacing: 1.3,
                        fontWeight: FontWeight.w700, color: BT.mut))),
                  ...recommended.map(_memberTile),
                ],
                if (others.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(left: 4, top: 6, bottom: 8),
                    child: Text(recommended.isEmpty ? 'TEAM' : 'OTHER ROLES',
                      style: const TextStyle(fontSize: 10.5, letterSpacing: 1.3,
                        fontWeight: FontWeight.w700, color: BT.mut))),
                  ...others.map(_memberTile),
                ],
                if (widget.stage.assigneeId != null) Padding(padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _apply(null),
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
      ),
    );
  }

  Widget _memberTile(Member m) {
    final selected = m.id == widget.stage.assigneeId;
    final confirming = _overrideFor == m.id;
    final load = ref.watch(workloadProvider).valueOrNull?[m.id] ?? 0;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: confirming ? BT.coral : (selected ? BT.ink : BT.line),
            width: (confirming || selected) ? 1.5 : 1)),
        child: Row(children: [
          Container(width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: roleColor(m.role), shape: BoxShape.circle),
            child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.w700, color: BT.ink))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name.isEmpty ? m.email : m.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 1),
            Text(load == 0 ? '${m.role} · free' : '${m.role} · $load open',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          if (confirming)
            const Text('Tap again', style: TextStyle(color: BT.coral, fontSize: 11.5, fontWeight: FontWeight.w700))
          else if (selected)
            const Icon(Icons.check_circle_rounded, color: BT.ink, size: 20),
        ]),
      ),
    ));
  }
}

/// Admin picks the project manager for a build.
class _PickPmSheet extends ConsumerWidget {
  final String? currentPmId;
  const _PickPmSheet({this.currentPmId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pms = ref.watch(pmsProvider);
    return Container(
      decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Text('Project manager', style: display(19, w: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('They will see this build, assign its stages and approve the work.',
            style: TextStyle(color: BT.mut, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 14),
          pms.when(
            loading: () => const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => Text('Could not load PMs.\n${friendlyError(e)}',
              style: const TextStyle(color: BT.coral, fontSize: 13)),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(icon: Icons.engineering_outlined, tint: BT.sky,
                  title: 'No project managers yet',
                  subtitle: 'Add one under Team → Add member with the PM role.');
              }
              return Column(children: list.map((p) {
                final selected = p.id == currentPmId;
                return Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: selected ? null : () => Navigator.pop(context, p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: selected ? BT.ink : BT.line, width: selected ? 1.5 : 1)),
                    child: Row(children: [
                      Container(width: 38, height: 38, alignment: Alignment.center,
                        decoration: const BoxDecoration(color: BT.sky, shape: BoxShape.circle),
                        child: Text(p.label.isNotEmpty ? p.label[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: BT.ink))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(p.label,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      if (selected) const Text('Current',
                        style: TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ));
              }).toList());
            },
          ),
        ]),
      ),
    );
  }
}



/// What the log-delay sheet hands back.
class _DelayResult {
  final String reason;
  final int days;
  final String? note;
  final bool pushDelivery;
  _DelayResult(this.reason, this.days, this.note, this.pushDelivery);
}

/// The delay_reason enum, with labels a PM reads.
const Map<String, String> _delayReasons = {
  'procurement': 'Procurement',
  'design_approval': 'Design approval',
  'workshop_capacity': 'Workshop capacity',
  'weather': 'Weather',
  'client': 'Client',
  'quality': 'Quality',
  'other': 'Other',
};

/// Bottom sheet: pick a reason, how many days, an optional note, and whether to
/// push the delivery date by the same amount.
class _LogDelaySheet extends StatefulWidget {
  final String stageName;
  const _LogDelaySheet({required this.stageName});
  @override
  State<_LogDelaySheet> createState() => _LogDelaySheetState();
}

class _LogDelaySheetState extends State<_LogDelaySheet> {
  String _reason = 'procurement';
  int _days = 1;
  bool _push = true;
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Text('Log a delay', style: display(19, w: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('On ${widget.stageName}', style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 16),
          const Text('REASON', style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _delayReasons.entries)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _reason = e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _reason == e.key ? BT.ink : BT.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _reason == e.key ? BT.ink : BT.line)),
                  child: Text(e.value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: _reason == e.key ? Colors.white : BT.mut))),
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Days delayed', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              height: 46,
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(behavior: HitTestBehavior.opaque, onTap: () { if (_days > 1) setState(() => _days--); },
                  child: const SizedBox(width: 42, height: 46, child: Icon(Icons.remove, size: 18))),
                SizedBox(width: 34, child: Text('$_days', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _days++),
                  child: const SizedBox(width: 42, height: 46, child: Icon(Icons.add, size: 18))),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(controller: _note, maxLines: 2,
              decoration: const InputDecoration(hintText: 'Note (optional)', border: InputBorder.none)),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _push = !_push),
            child: Row(children: [
              Icon(_push ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: _push ? BT.ink : BT.mut2, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('Push delivery date by these days',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
            ]),
          ),
          const SizedBox(height: 18),
          PrimaryButton('Log delay', icon: Icons.check,
            onTap: () => Navigator.pop(context, _DelayResult(_reason, _days,
              _note.text.trim().isEmpty ? null : _note.text.trim(), _push))),
        ]),
      ),
    );
  }
}

/// doc_type enum → labels staff and clients read.
const Map<String, String> _docTypeLabels = {
  'contract': 'Contract',
  'invoice': 'Invoice',
  'warranty_pack': 'Warranty pack',
  'handover_cert': 'Handover certificate',
};

/// Best-effort content type from a filename, so an uploaded PDF opens as a PDF
/// and an image as an image rather than a download.
String _docContentType(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

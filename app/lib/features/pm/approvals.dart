import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// PM — Approvals (p7): stage completions submitted by workshop.
///
/// Each card now shows the *evidence* the assignee submitted — the site photos,
/// the checklist, and the parts installed on that stage — so the PM decides on
/// what was actually done rather than on a stage name alone. Approving blind was
/// the real risk here: on a factory floor a "done" with no photo and an
/// unfinished checklist is exactly what a PM needs to catch before it moves on.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvals = ref.watch(pendingApprovalsProvider);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(pendingApprovalsProvider.future),
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
            ]),
            const SizedBox(height: 14),
            Text('Approvals', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Review the work, then approve or send it back.',
              style: TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 16),
            approvals.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load approvals.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                    title: 'Nothing to approve', subtitle: 'Stage completions from workshop will show here.')
                : Column(children: [for (final a in list) _ApprovalCard(a)]),
            ),
          ],
        ),
      )),
    );
  }
}

/// One submission: header, the evidence bundle, and the approve/reject actions.
class _ApprovalCard extends ConsumerWidget {
  const _ApprovalCard(this.a);
  final ApprovalItem a;

  Future<void> _decide(BuildContext context, WidgetRef ref, bool approve) async {
    // Sending work back without saying why leaves the assignee guessing, so ask.
    String? note;
    if (!approve) {
      note = await _askReason(context);
      if (note == null) return; // cancelled
    }
    try {
      await ref.read(projectsRepoProvider).decideApproval(a.id, approve, note: note);
      ref.invalidate(pendingApprovalsProvider);
      ref.invalidate(pmDashboardProvider);
      ref.invalidate(myProjectsProvider);
      ref.invalidate(stagesToAssignProvider);
      ref.invalidate(workloadProvider);
      ref.invalidate(notificationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink,
          content: Text(approve
            ? '${a.projectCode} · ${a.stageName} approved — next stage started'
            : '${a.projectCode} · ${a.stageName} sent back for rework')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral, content: Text(friendlyError(e))));
      }
    }
  }

  /// Reject reason — stored on the submission and pushed to the assignee.
  Future<String?> _askReason(BuildContext context) async {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Send back', style: display(18, w: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${a.projectCode} · ${a.stageName}',
          style: const TextStyle(color: BT.mut, fontSize: 12.5)),
        const SizedBox(height: 10),
        Container(decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(controller: c, maxLines: 3,
            decoration: const InputDecoration(hintText: 'What needs fixing?', border: InputBorder.none))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()),
          child: const Text('Send back', style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(stageBundleProvider(a.stageId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.check_rounded, color: BT.ink)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a.stageName} · done', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text([
                a.projectCode,
                if (a.submittedBy != null && a.submittedBy!.isNotEmpty) a.submittedBy!,
              ].join(' · '), style: const TextStyle(color: BT.mut, fontSize: 12)),
            ])),
          ]),

          // ── the evidence ─────────────────────────────────────────────────
          bundle.when(
            loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut)))),
            error: (e, _) => Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('Could not load the submitted work.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 12))),
            data: (b) => _evidence(context, b),
          ),

          const SizedBox(height: 13),
          Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _decide(context, ref, false),
              child: Container(height: 44, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.close_rounded, size: 17, color: BT.ink), SizedBox(width: 6),
                  Text('Reject', style: TextStyle(fontWeight: FontWeight.w600)),
                ])),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _decide(context, ref, true),
              child: Container(height: 44, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(13)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_rounded, size: 17, color: BT.ink), SizedBox(width: 6),
                  Text('Approve', style: TextStyle(fontWeight: FontWeight.w600)),
                ])),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _evidence(BuildContext context, StageBundle b) {
    final doneCount = b.checklist.where((c) => c.done).length;
    final total = b.checklist.length;
    final allDone = total > 0 && doneCount == total;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),

      // Photos — the fastest read on whether the work is really done. No photo
      // is itself a signal, so it is called out rather than left blank.
      if (b.photos.isEmpty)
        _flag(Icons.no_photography_outlined, 'No photos attached', BT.amber)
      else
        SizedBox(height: 76, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: b.photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final p = b.photos[i];
            return GestureDetector(
              onTap: () => _openPhoto(context, p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(p.url, width: 76, height: 76, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 76, height: 76,
                    color: BT.card2, alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, color: BT.mut2, size: 22)),
                  loadingBuilder: (ctx, child, progress) => progress == null ? child
                    : Container(width: 76, height: 76, color: BT.card2, alignment: Alignment.center,
                        child: const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut2)))),
              ),
            );
          },
        )),

      const SizedBox(height: 12),

      // Checklist — "5 of 6 done", and an incomplete list is worth pausing on.
      if (total > 0) ...[
        Row(children: [
          Icon(allDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 16, color: allDone ? BT.ink : BT.amber),
          const SizedBox(width: 6),
          Text('Checklist · $doneCount of $total',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: allDone ? BT.ink : const Color(0xFF8A6D1E))),
        ]),
        const SizedBox(height: 8),
        ...b.checklist.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(c.done ? Icons.check_rounded : Icons.close_rounded,
              size: 15, color: c.done ? const Color(0xFF3A4A12) : BT.coral),
            const SizedBox(width: 7),
            Expanded(child: Text(c.label, style: TextStyle(fontSize: 12.5,
              color: c.done ? BT.mut : BT.ink,
              decoration: c.done ? TextDecoration.lineThrough : null,
              decorationColor: BT.mut2))),
          ]),
        )),
        const SizedBox(height: 4),
      ] else
        _flag(Icons.checklist_rtl_rounded, 'No checklist on this stage', BT.mut2),

      // Parts installed on this stage (Hero #2 traceability, at a glance).
      if (b.parts.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 15, color: BT.mut),
          const SizedBox(width: 6),
          Text('${b.parts.length} part${b.parts.length == 1 ? '' : 's'} installed',
            style: const TextStyle(fontSize: 12.5, color: BT.mut, fontWeight: FontWeight.w600)),
        ]),
      ],
    ]);
  }

  Widget _flag(IconData icon, String label, Color tint) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(11)),
    child: Row(children: [
      Icon(icon, size: 16, color: tint),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 12.5, color: BT.mut, fontWeight: FontWeight.w500)),
    ]),
  );

  /// Full-screen, zoomable view of a single site photo.
  void _openPhoto(BuildContext context, StagePhoto p) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white,
        title: Text(p.caption ?? 'Work photo', style: const TextStyle(fontSize: 15))),
      body: Center(child: InteractiveViewer(
        child: Image.network(p.url, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('Could not load photo',
            style: TextStyle(color: Colors.white70))),
      )),
    )));
  }
}

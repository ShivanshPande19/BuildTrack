import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
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
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              BackChip(),
            ]),
            const SizedBox(height: 14),
            Text('Approvals', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Review the work, then approve or send it back.',
              style: TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 16),
            ContentReveal(child: approvals.when(
              loading: () => const SkeletonList(count: 3),
              error: (e, _) => ErrorCard('Could not load approvals.\n${friendlyError(e)}', onRetry: () => ref.invalidate(pendingApprovalsProvider)),
              data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                    title: 'Nothing to approve', subtitle: 'Stage completions from workshop will show here.')
                : Column(children: [
                    // Keyed by id: when one is decided and drops out, the next card
                    // must not inherit its state (busy / folded away).
                    for (final a in list) _ApprovalCard(a, key: ValueKey(a.id)),
                  ]),
            )),
          ],
        ),
      )),
    );
  }
}

/// One submission: header, the evidence bundle, and the approve/reject actions.
class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard(this.a, {super.key});
  final ApprovalItem a;
  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _deciding = false;
  bool _approving = false; // which button is in flight, so that one spins
  bool _gone = false;      // decided: fade the card out…
  bool _folded = false;    // …then fold its space shut, before the list refreshes
  ApprovalItem get a => widget.a;

  Future<void> _decide(bool approve) async {
    if (_deciding) return; // guard a fast double-tap firing two decisions
    // Sending work back without saying why leaves the assignee guessing, so ask.
    String? note;
    if (!approve) {
      note = await _askReason(context);
      if (note == null || !mounted) return; // cancelled
    }
    // The container and messenger outlive this card, which is removed below.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() { _deciding = true; _approving = approve; });
    try {
      await ref.read(projectsRepoProvider).decideApproval(a.id, approve, note: note);
      Haptic.confirm();
      // Fold the card shut first, then refresh the list. If the list refreshed
      // first, the card would blink out and everything below would jump up.
      if (mounted) setState(() => _gone = true);
      await Future<void>.delayed(Motion.fast);
      if (mounted) setState(() => _folded = true);
      await Future<void>.delayed(Motion.base);
      container
        ..invalidate(pendingApprovalsProvider)
        ..invalidate(pmDashboardProvider)
        ..invalidate(myProjectsProvider)
        ..invalidate(stagesToAssignProvider)
        ..invalidate(workloadProvider)
        ..invalidate(notificationsProvider);
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(
          backgroundColor: BT.ink,
          content: Text(approve
            ? '${a.projectCode} · ${a.stageName} approved — next stage started'
            : '${a.projectCode} · ${a.stageName} sent back for rework')));
      }
    } catch (e) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  Widget _decisionButton(String label, IconData icon, Color bg, {required bool approve}) {
    final busy = _deciding && _approving == approve;
    final locked = _deciding && !busy;
    return PressableScale(
      haptic: true,
      onTap: _deciding ? null : () => _decide(approve),
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: locked ? 0.5 : 1,
        child: Container(height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
          child: AnimatedSwap(child: busy
            ? const SizedBox(key: ValueKey('busy'), width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: BT.ink))
            : Row(key: const ValueKey('label'), mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17, color: BT.ink), const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]))),
      ),
    );
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
  Widget build(BuildContext context) {
    final bundle = ref.watch(stageBundleProvider(a.stageId));
    final card = Padding(
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
          ContentReveal(child: bundle.when(
            loading: () => const _EvidenceSkeleton(),
            error: (e, _) => Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('Could not load the submitted work.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 12))),
            data: (b) => _evidence(context, b),
          )),

          const SizedBox(height: 13),
          // Both buttons stay put; the tapped one spins and the other locks.
          Row(children: [
            Expanded(child: _decisionButton('Reject', Icons.close_rounded, BT.card2, approve: false)),
            const SizedBox(width: 10),
            Expanded(child: _decisionButton('Approve', Icons.check_rounded, BT.lime, approve: true)),
          ]),
        ]),
      ),
    );
    if (reduceMotion(context)) return _gone ? const SizedBox.shrink() : card;
    // Decided cards fade out (the card stays while it fades), then their space
    // folds shut so the cards below glide up instead of jumping.
    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.move,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: _gone ? 0 : 1,
        child: _folded ? const SizedBox(width: double.infinity) : card,
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

/// Placeholder for the photo strip + checklist while a submission loads.
class _EvidenceSkeleton extends StatelessWidget {
  const _EvidenceSkeleton();
  @override
  Widget build(BuildContext context) => const Shimmer(
    child: Padding(
      padding: EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SkeletonBox(width: 76, height: 76, radius: 12), SizedBox(width: 8),
          SkeletonBox(width: 76, height: 76, radius: 12), SizedBox(width: 8),
          SkeletonBox(width: 76, height: 76, radius: 12),
        ]),
        SizedBox(height: 14),
        SkeletonBox(width: 140, height: 12),
        SizedBox(height: 9),
        SkeletonBox(width: 200, height: 10),
      ]),
    ),
  );
}

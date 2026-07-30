import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// PM — Approvals (p7): stage completions submitted by workshop. Approve / reject.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  Future<void> _decide(BuildContext context, WidgetRef ref, ApprovalItem a, bool approve) async {
    // Sending work back without saying why leaves the assignee guessing, so ask.
    String? note;
    if (!approve) {
      note = await _askReason(context, a);
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
  Future<String?> _askReason(BuildContext context, ApprovalItem a) async {
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
            const Text('Stage completions submitted by workshop.',
              style: TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 16),
            approvals.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load approvals.\n$e',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                    title: 'Nothing to approve', subtitle: 'Stage completions from workshop will show here.')
                : Column(children: list.map((a) => _card(context, ref, a)).toList()),
            ),
          ],
        ),
      )),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, ApprovalItem a) => Padding(
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
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _decide(context, ref, a, false),
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
            onTap: () => _decide(context, ref, a, true),
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

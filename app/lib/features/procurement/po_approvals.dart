import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'po_detail.dart';

/// PO Approvals inbox — the queue of purchase orders waiting on a signature.
///
/// Role-aware: a PM sees the project POs waiting for *their* signature; the
/// owner / admin sees everything awaiting final approval (plus, for visibility,
/// what is still sitting with a PM). Each row shows the amount and **how long it
/// has been waiting**, with overdue ones flagged — so a late signature that is
/// about to slip an order is impossible to miss. Tapping opens the PO to sign,
/// approve or reject after seeing the items and the amount.
class PoApprovalsScreen extends ConsumerWidget {
  const PoApprovalsScreen({super.key});

  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  String _waited(double hours) {
    if (hours < 1) return 'just now';
    if (hours < 24) return 'waiting ${hours.round()}h';
    return 'waiting ${(hours / 24).floor()}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(myRoleProvider).valueOrNull;
    final uid = sb.auth.currentUser?.id;
    final approvals = ref.watch(poApprovalsProvider);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(poApprovalsProvider.future),
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
            Text('PO Approvals', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(role == 'admin'
              ? 'Purchase orders waiting for your final sign-off.'
              : 'Purchase orders on your builds waiting for your signature.',
              style: const TextStyle(color: BT.mut, fontSize: 12.5)),
            const SizedBox(height: 16),
            approvals.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load approvals.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) {
                int byPriority(PoApproval a, PoApproval b) {
                  final p = a.priorityRank.compareTo(b.priorityRank);
                  return p != 0 ? p : b.waitingHours.compareTo(a.waitingHours);
                }
                final mine = (role == 'admin'
                    ? list.where((a) => a.awaitingFinal).toList()
                    : list.where((a) => a.awaitingPm && a.pmId == uid).toList())
                  ..sort(byPriority);
                // Admin also gets visibility of what is still with a PM.
                final withPm = (role == 'admin' ? list.where((a) => a.awaitingPm).toList() : <PoApproval>[])
                  ..sort(byPriority);

                if (mine.isEmpty && withPm.isEmpty) {
                  return const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                    title: 'Nothing to approve', subtitle: 'Purchase orders needing a signature will show here.');
                }
                final canPrioritise = role == 'admin';
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (mine.isNotEmpty) ...[
                    SectionLabel(role == 'admin' ? 'Needs your approval · by priority' : 'Needs your signature · by priority'),
                    ...mine.map((a) => _row(context, ref, a, actionable: true, canPrioritise: canPrioritise)),
                  ],
                  if (withPm.isNotEmpty) ...[
                    const SectionLabel('Still with the project manager'),
                    ...withPm.map((a) => _row(context, ref, a, actionable: false, canPrioritise: canPrioritise)),
                  ],
                ]);
              },
            ),
          ],
        ),
      )),
    );
  }

  ({String label, Color color}) _prio(String p) => switch (p) {
    'critical' => (label: 'Critical', color: BT.coral),
    'high'     => (label: 'High', color: BT.amber),
    'medium'   => (label: 'Medium', color: BT.sky),
    _          => (label: 'Low', color: BT.mut2),
  };

  Widget _row(BuildContext context, WidgetRef ref, PoApproval a,
      {required bool actionable, required bool canPrioritise}) {
    final tint = a.overdue ? BT.coral : (a.waitingHours >= 24 ? BT.amber : BT.sky);
    final pr = _prio(a.priority);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PoDetailScreen(poId: a.id, poNumber: a.poNumber))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BT.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            color: BT.card, borderRadius: BorderRadius.circular(BT.radiusCard), border: Border.all(color: BT.line),
            boxShadow: const [BoxShadow(color: Color(0x11695228), blurRadius: 24, offset: Offset(0, 12))]),
          child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // priority accent stripe
            Container(width: 5, color: pr.color),
            Expanded(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(a.poNumber, style: display(15, w: FontWeight.w600)),
                      if (a.amount > 0) ...[
                        const SizedBox(width: 8),
                        Text(_money.format(a.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text('${a.vendorName ?? 'Vendor'} · ${a.projectCode ?? 'General stock'}',
                      style: const TextStyle(color: BT.mut, fontSize: 12)),
                  ])),
                  // priority badge — tappable for the admin to override
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canPrioritise ? () => _setPriority(context, ref, a) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: pr.color, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(pr.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BT.ink)),
                        if (canPrioritise) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.expand_more_rounded, size: 14, color: BT.ink),
                        ],
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 11),
                Row(children: [
                  StatusPill(a.overdue ? 'Order-by passed' : _waited(a.waitingHours), color: tint),
                  const Spacer(),
                  if (actionable)
                    Text(a.awaitingFinal ? 'Tap to approve' : 'Tap to sign',
                      style: const TextStyle(color: BT.mut, fontSize: 12, fontWeight: FontWeight.w600))
                  else
                    const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                ]),
              ]),
            )),
          ])),
        ),
      ),
    ));
  }

  /// Admin bumps or clears a PO's priority (override wins over the auto rule).
  Future<void> _setPriority(BuildContext context, WidgetRef ref, PoApproval a) async {
    Future<void> apply(String? p) async {
      Navigator.pop(context);
      try {
        await ref.read(procurementRepoProvider).setPoPriority(a.id, p);
        ref.invalidate(poApprovalsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: BT.coral, content: Text(friendlyError(e))));
        }
      }
    }
    await showModalBottomSheet<void>(
      context: context, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Text('Set priority · ${a.poNumber}', style: display(18, w: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Overrides the automatic order-by priority.', style: TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 14),
          for (final p in const ['critical', 'high', 'medium', 'low']) _prioOption(context, p, () => apply(p)),
          const SizedBox(height: 4),
          _prioOption(context, 'auto', () => apply(null)),
        ]),
      ),
    );
  }

  Widget _prioOption(BuildContext context, String p, VoidCallback onTap) {
    final isAuto = p == 'auto';
    final info = isAuto ? (label: 'Automatic (by order-by date)', color: BT.card2) : _prio(p);
    return Padding(padding: const EdgeInsets.only(bottom: 9), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
        child: Row(children: [
          Container(width: 14, height: 14,
            decoration: BoxDecoration(color: info.color, shape: BoxShape.circle,
              border: isAuto ? Border.all(color: BT.mut2) : null)),
          const SizedBox(width: 12),
          Text(info.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BT.ink)),
        ]),
      ),
    ));
  }
}

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
                final mine = role == 'admin'
                    ? list.where((a) => a.awaitingFinal).toList()
                    : list.where((a) => a.awaitingPm && a.pmId == uid).toList();
                // Admin also gets visibility of what is still with a PM.
                final withPm = role == 'admin' ? list.where((a) => a.awaitingPm).toList() : <PoApproval>[];

                if (mine.isEmpty && withPm.isEmpty) {
                  return const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                    title: 'Nothing to approve', subtitle: 'Purchase orders needing a signature will show here.');
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (mine.isNotEmpty) ...[
                    SectionLabel(role == 'admin' ? 'Needs your approval' : 'Needs your signature'),
                    ...mine.map((a) => _row(context, a, actionable: true)),
                  ],
                  if (withPm.isNotEmpty) ...[
                    const SectionLabel('Still with the project manager'),
                    ...withPm.map((a) => _row(context, a, actionable: false)),
                  ],
                ]);
              },
            ),
          ],
        ),
      )),
    );
  }

  Widget _row(BuildContext context, PoApproval a, {required bool actionable}) {
    final tint = a.overdue ? BT.coral : (a.waitingHours >= 24 ? BT.amber : BT.sky);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PoDetailScreen(poId: a.id, poNumber: a.poNumber))),
      child: AppCard(padding: const EdgeInsets.all(16),
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
            const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            StatusPill(a.overdue ? 'Order-by passed' : _waited(a.waitingHours), color: tint),
            const Spacer(),
            if (actionable)
              Text(a.awaitingFinal ? 'Tap to approve' : 'Tap to sign',
                style: const TextStyle(color: BT.mut, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    ));
  }
}

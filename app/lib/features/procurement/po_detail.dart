import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'new_po.dart';

/// Procurement / PM / Admin — PO detail (pr3).
///
/// Shows the approval chain first (raised → PM signs → final approval), with the
/// signature trail and the right action for whoever is looking at it. Only once
/// the PO is approved does the fulfilment tracker (ordered → dispatched →
/// received) become live — dispatching before approval is refused by the
/// database, so it isn't offered here.
class PoDetailScreen extends ConsumerWidget {
  final String poId;
  final String? poNumber; // for instant header
  const PoDetailScreen({super.key, required this.poId, this.poNumber});

  static final _fmt = DateFormat('d MMM');
  static final _fmtDt = DateFormat('d MMM · h:mm a');
  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  ({String label, Color color}) _statusPill(PurchaseOrder o) {
    if (o.isRejected)      return (label: 'Rejected', color: BT.coral);
    if (o.isAwaitingPm)    return (label: 'Awaiting PM', color: BT.lav);
    if (o.isAwaitingFinal) return (label: 'Awaiting approval', color: BT.amber);
    return switch (o.status) {
      'ordered'    => (label: 'Ordered', color: BT.sky),
      'dispatched' => (label: 'Dispatched', color: BT.amber),
      'received'   => (label: 'Received', color: BT.lime),
      'partial'    => (label: 'Partial', color: BT.amber),
      _            => (label: o.status, color: BT.mut2),
    };
  }

  int _stepIndex(String s) => switch (s) {
    'ordered'    => 0,
    'dispatched' => 1,
    'partial'    => 1,
    'received'   => 2,
    _            => 0,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(poDetailProvider(poId));
    final role = ref.watch(myRoleProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(poDetailProvider(poId).future),
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
              detail.maybeWhen(
                data: (d) { final s = _statusPill(d.po); return StatusPill(s.label, color: s.color); },
                orElse: () => const SizedBox.shrink()),
            ]),
            const SizedBox(height: 14),
            Text(poNumber ?? '', style: display(29, w: FontWeight.w500)),
            detail.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 16),
                child: AppCard(child: Text('Could not load PO.\n${friendlyError(e)}',
                  style: const TextStyle(color: BT.coral, fontSize: 13)))),
              data: (d) => _content(context, ref, d, role),
            ),
          ],
        ),
      )),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, PoDetail d, String? role) {
    final po = d.po;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${po.vendorName ?? 'Vendor'} · ${po.projectCode ?? 'General stock'}',
          style: const TextStyle(color: BT.mut, fontSize: 13))),
        if (po.amount > 0)
          Text(_money.format(po.amount), style: display(18, w: FontWeight.w700)),
      ]),
      const SizedBox(height: 16),

      // ── Approval, while the PO is still being signed / was rejected ──────
      if (po.isPendingApproval || po.isRejected) _approvalCard(context, ref, d, role),

      // ── Fulfilment tracker — only meaningful once approved ──────────────
      if (po.isApproved) ...[
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(children: [
            Row(children: [
              _step('Ordered', 0, _stepIndex(po.status)),
              _connector(_stepIndex(po.status) >= 1),
              _step('Dispatched', 1, _stepIndex(po.status)),
              _connector(_stepIndex(po.status) >= 2),
              _step('Received', 2, _stepIndex(po.status)),
            ]),
            if (po.expectedDate != null) ...[
              const SizedBox(height: 12),
              Text('Expected delivery · ${_fmt.format(po.expectedDate!)}',
                style: const TextStyle(color: BT.mut, fontSize: 12)),
            ],
          ]),
        ),
      ],

      // ── Items, with rate + GST ──────────────────────────────────────────
      SectionLabel('Items · ${d.items.length}'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: [
          for (int i = 0; i < d.items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(border: Border(
                bottom: BorderSide(color: i == d.items.length - 1 ? Colors.transparent : BT.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.items[i].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (d.items[i].unitPrice > 0) Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text('${d.items[i].qty} × ${_money.format(d.items[i].unitPrice)} · ${d.items[i].taxRate.toInt()}% GST',
                      style: const TextStyle(color: BT.mut, fontSize: 12))),
                ])),
                Text(d.items[i].unitPrice > 0
                    ? _money.format(d.items[i].lineTotal)
                    : '×${d.items[i].qty}',
                  style: display(14, w: FontWeight.w600, c: BT.mut)),
              ]),
            ),
          if (po.amount > 0) ...[
            const Divider(height: 1, color: BT.line),
            Padding(padding: const EdgeInsets.symmetric(vertical: 11),
              child: Column(children: [
                _totalRow('Subtotal', _money.format(po.subtotal), muted: true),
                const SizedBox(height: 5),
                _totalRow('GST', _money.format(po.taxTotal), muted: true),
                const SizedBox(height: 8),
                _totalRow('Total', _money.format(po.amount)),
              ])),
          ],
        ]),
      ),

      if (po.paymentTerms != null && po.paymentTerms!.isNotEmpty) ...[
        const SizedBox(height: 12),
        _infoLine(Icons.payments_outlined, 'Payment', po.paymentTerms!),
      ],

      // Dispatch / receive is procurement's (or admin's) job — a PM who opened
      // this to sign it doesn't get those buttons.
      if (po.isApproved && (role == 'procurement' || role == 'admin')) ...[
        const SizedBox(height: 18),
        _actionButton(context, ref, po.status),
      ],
    ]);
  }

  // ── Approval card: stepper + signature trail + the right action ─────────
  Widget _approvalCard(BuildContext context, WidgetRef ref, PoDetail d, String? role) {
    final po = d.po;
    final uid = sb.auth.currentUser?.id;
    final isProjectPo = po.pmId != null;

    final canPmSign = role == 'pm' && po.isAwaitingPm && po.pmId == uid;
    final canFinal  = role == 'admin' && po.isAwaitingFinal;
    final canReject = (role == 'admin' && po.isPendingApproval) ||
                      (role == 'pm' && po.isAwaitingPm && po.pmId == uid);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('APPROVAL',
            style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, color: BT.mut, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          if (po.isRejected)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(13)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.cancel_outlined, size: 18, color: BT.coral),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Rejected', style: TextStyle(fontWeight: FontWeight.w700, color: BT.coral, fontSize: 13.5)),
                  if (po.rejectionReason != null && po.rejectionReason!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(po.rejectionReason!, style: const TextStyle(fontSize: 12.5, height: 1.3)),
                  ],
                ])),
              ]),
            )
          else ...[
            // horizontal stepper: raised → (PM signed) → approved
            Row(children: [
              _astep('Raised', true, false),
              _connector(true),
              if (isProjectPo) ...[
                _astep('PM signed', po.pmSignedAt != null, po.isAwaitingPm),
                _connector(po.pmSignedAt != null),
              ],
              _astep('Approved', po.isApproved, po.isAwaitingFinal),
            ]),
            const SizedBox(height: 6),
            Text(
              po.isAwaitingPm
                ? 'Waiting on the project manager to sign.'
                : 'Waiting on final approval from an owner / admin.',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ],

          // signature trail (the delay log: who, when)
          if (d.events.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: BT.line)),
            ...d.events.map(_trailRow),
          ],
        ]),
      ),

      const SizedBox(height: 12),
      if (canPmSign)
        PrimaryButton('Sign & send for approval', icon: Icons.draw_rounded, bg: BT.ink, fg: BT.card,
          onTap: () => _run(context, ref, () => ref.read(procurementRepoProvider).pmSignPo(poId),
            'Signed — sent for final approval.')),
      if (canFinal)
        PrimaryButton('Approve — place the order', icon: Icons.verified_rounded, bg: BT.ink, fg: BT.card,
          onTap: () => _run(context, ref, () => ref.read(procurementRepoProvider).finalApprovePo(poId),
            'Approved — the order can be placed.')),
      if (canReject) Padding(
        padding: EdgeInsets.only(top: (canPmSign || canFinal) ? 10 : 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final reason = await _askReason(context);
            if (reason == null || reason.trim().isEmpty) return;
            if (!context.mounted) return;
            await _run(context, ref, () => ref.read(procurementRepoProvider).rejectPo(poId, reason.trim()),
              'Rejected — sent back to procurement.');
          },
          child: Container(height: 50, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(16)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.close_rounded, size: 18, color: BT.ink), SizedBox(width: 8),
              Text('Reject', style: TextStyle(fontWeight: FontWeight.w600)),
            ])),
        ),
      ),
      // A sent-back PO is procurement's to fix and resubmit — the rework loop.
      if (po.isRejected && (role == 'procurement' || role == 'admin'))
        PrimaryButton('Fix & resubmit', icon: Icons.edit_rounded, bg: BT.ink, fg: BT.card,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NewPoScreen(editPo: d)))),
      if (!canPmSign && !canFinal && !canReject && po.isPendingApproval)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.hourglass_top_rounded, size: 17, color: BT.mut),
            const SizedBox(width: 8),
            Expanded(child: Text(
              po.isAwaitingPm ? 'Awaiting the project manager\'s signature.' : 'Awaiting final approval.',
              style: const TextStyle(color: BT.mut, fontSize: 12.5))),
          ]),
        ),
      const SizedBox(height: 18),
    ]);
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String msg) async {
    try {
      await action();
      ref.invalidate(poDetailProvider(poId));
      ref.invalidate(purchaseOrdersProvider);
      ref.invalidate(poApprovalsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: BT.ink, content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
      }
    }
  }

  Future<String?> _askReason(BuildContext context) async {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Reject PO', style: display(18, w: FontWeight.w600)),
      content: Container(decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(controller: c, maxLines: 3,
          decoration: const InputDecoration(hintText: 'Why is this being rejected?', border: InputBorder.none))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()),
          child: const Text('Reject', style: TextStyle(color: BT.coral, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  Widget _trailRow(PoApprovalEvent e) {
    final (icon, label, tint) = switch (e.event) {
      'created'      => (Icons.edit_note_rounded, 'Raised', BT.sky),
      'pm_signed'    => (Icons.draw_rounded, 'Signed by PM', BT.lav),
      'final_signed' => (Icons.verified_rounded, 'Final approval', BT.lime),
      'rejected'     => (Icons.close_rounded, 'Rejected', BT.coral),
      _              => (Icons.circle, e.event, BT.mut2),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: BT.ink)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (e.actorName != null && e.actorName!.isNotEmpty) ...[
              const Text(' · ', style: TextStyle(color: BT.mut2)),
              Flexible(child: Text(e.actorName!, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BT.mut, fontSize: 12.5))),
            ],
          ]),
          if (e.at != null) Text(_fmtDt.format(e.at!), style: const TextStyle(color: BT.mut2, fontSize: 11)),
          if (e.note != null && e.note!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(e.note!, style: const TextStyle(color: BT.mut, fontSize: 12, fontStyle: FontStyle.italic))),
        ])),
      ]),
    );
  }

  Widget _totalRow(String label, String value, {bool muted = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(fontSize: muted ? 13 : 15,
      fontWeight: muted ? FontWeight.w500 : FontWeight.w700, color: muted ? BT.mut : BT.ink)),
    Text(value, style: muted
      ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BT.mut)
      : display(17, w: FontWeight.w700)),
  ]);

  Widget _infoLine(IconData icon, String label, String value) => Row(children: [
    Icon(icon, size: 16, color: BT.mut),
    const SizedBox(width: 8),
    Text('$label · ', style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600)),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5))),
  ]);

  Widget _actionButton(BuildContext context, WidgetRef ref, String status) {
    final repo = ref.read(procurementRepoProvider);
    if (status == 'ordered') {
      return PrimaryButton('Mark as dispatched', icon: Icons.local_shipping_rounded,
        bg: BT.ink, fg: BT.card,
        onTap: () async {
          final now = DateTime.now();
          final eta = await showDatePicker(context: context,
            initialDate: now.add(const Duration(days: 7)),
            firstDate: now, lastDate: now.add(const Duration(days: 365)),
            helpText: 'Expected arrival date');
          if (eta == null || !context.mounted) return;
          await _run(context, ref, () => repo.markDispatched(poId, expectedDate: eta),
            'PO dispatched · arriving ${_fmt.format(eta)}');
        });
    }
    if (status == 'received') {
      return Container(
        height: 52, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(16)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, color: BT.lime, size: 19),
          SizedBox(width: 8),
          Text('Received', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
    }
    return PrimaryButton('Mark as received', icon: Icons.inventory_2_rounded,
      bg: BT.ink, fg: BT.card,
      onTap: () => _run(context, ref, () => repo.markReceived(poId), 'Marked received — Store can now log components.'));
  }

  // fulfilment stepper node
  Widget _step(String label, int index, int current) {
    final done = index < current;
    final now = index == current;
    Widget circle;
    if (done) {
      circle = Container(width: 26, height: 26, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 14, color: BT.ink));
    } else if (now) {
      circle = Container(width: 26, height: 26, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle),
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
    } else {
      circle = Container(width: 26, height: 26,
        decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 2)));
    }
    return Column(children: [
      circle,
      const SizedBox(height: 7),
      Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600,
        color: (done || now) ? BT.ink : BT.mut)),
    ]);
  }

  // approval stepper node
  Widget _astep(String label, bool done, bool active) {
    Widget circle;
    if (done) {
      circle = Container(width: 26, height: 26, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 14, color: BT.ink));
    } else if (active) {
      circle = Container(width: 26, height: 26, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle),
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
    } else {
      circle = Container(width: 26, height: 26,
        decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 2)));
    }
    return Column(children: [
      circle,
      const SizedBox(height: 7),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
        color: (done || active) ? BT.ink : BT.mut)),
    ]);
  }

  Widget _connector(bool active) => Expanded(child: Container(
    height: 2, margin: const EdgeInsets.only(bottom: 20),
    color: active ? BT.lime : BT.line));
}

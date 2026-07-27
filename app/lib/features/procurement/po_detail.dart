import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Procurement — PO detail (pr3): status stepper, items, mark received.
class PoDetailScreen extends ConsumerWidget {
  final String poId;
  final String? poNumber; // for instant header
  const PoDetailScreen({super.key, required this.poId, this.poNumber});

  static final _fmt = DateFormat('d MMM');

  ({String label, Color color}) _statusPill(String s) => switch (s) {
    'ordered'    => (label: 'Ordered', color: BT.sky),
    'dispatched' => (label: 'Dispatched', color: BT.amber),
    'received'   => (label: 'Received', color: BT.lime),
    'partial'    => (label: 'Partial', color: BT.amber),
    _            => (label: s, color: BT.mut2),
  };

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
                data: (d) { final s = _statusPill(d.po.status); return StatusPill(s.label, color: s.color); },
                orElse: () => const SizedBox.shrink()),
            ]),
            const SizedBox(height: 14),
            Text(poNumber ?? '', style: display(29, w: FontWeight.w500)),
            detail.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 16),
                child: AppCard(child: Text('Could not load PO.\n$e',
                  style: const TextStyle(color: BT.coral, fontSize: 13)))),
              data: (d) => _content(context, ref, d),
            ),
          ],
        ),
      )),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, PoDetail d) {
    final step = _stepIndex(d.po.status);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${d.po.vendorName ?? 'Vendor'} · ${d.po.projectCode ?? '—'}',
        style: const TextStyle(color: BT.mut, fontSize: 13)),
      const SizedBox(height: 16),

      AppCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(children: [
          Row(children: [
            _step('Ordered', 0, step),
            _connector(step >= 1),
            _step('Dispatched', 1, step),
            _connector(step >= 2),
            _step('Received', 2, step),
          ]),
          if (d.po.expectedDate != null) ...[
            const SizedBox(height: 12),
            Text('Expected delivery · ${_fmt.format(d.po.expectedDate!)}',
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ],
        ]),
      ),

      SectionLabel('Items · ${d.items.length}'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: [
          for (int i = 0; i < d.items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(border: Border(
                bottom: BorderSide(color: i == d.items.length - 1 ? Colors.transparent : BT.line))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(d.items[i].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                Text('×${d.items[i].qty}', style: display(14, w: FontWeight.w600, c: BT.mut)),
              ]),
            ),
        ]),
      ),

      const SizedBox(height: 18),
      if (d.po.status != 'received')
        PrimaryButton('Mark as received', icon: Icons.local_shipping_rounded,
          bg: BT.ink, fg: BT.card,
          onTap: () async {
            await ref.read(procurementRepoProvider).markReceived(poId);
            ref.invalidate(poDetailProvider(poId));
            ref.invalidate(purchaseOrdersProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: BT.ink, content: Text('Marked received — Store can now log components.')));
            }
          })
      else
        Container(
          height: 52, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(16)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, color: BT.lime, size: 19),
            SizedBox(width: 8),
            Text('Received', style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
    ]);
  }

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

  Widget _connector(bool active) => Expanded(child: Container(
    height: 2, margin: const EdgeInsets.only(bottom: 20),
    color: active ? BT.lime : BT.line));
}

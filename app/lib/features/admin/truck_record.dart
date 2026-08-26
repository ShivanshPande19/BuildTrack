import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — the truck's complete physical record.
///
/// Every component ever fitted to this build in one place: item + model, serial,
/// vendor, the stage it went into and who installed it, its warranty state, and
/// its bill — plus the build's documents. The digital twin of the truck, so a
/// warranty claim, an audit or a handover pack never means hunting stage by
/// stage.
class TruckRecordScreen extends ConsumerWidget {
  const TruckRecordScreen({super.key, required this.projectId, this.code, this.name});
  final String projectId;
  final String? code, name;

  static final _fmt = DateFormat('d MMM yyyy');
  static String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  ({String label, Color color}) _warranty(String state) => switch (state) {
    'active'   => (label: 'Warranty active', color: BT.lime),
    'expiring' => (label: 'Expiring soon', color: BT.amber),
    'expired'  => (label: 'Expired', color: BT.coral),
    _          => (label: 'No warranty', color: BT.mut2),
  };

  static const _docLabels = {
    'contract': 'Contract', 'invoice': 'Invoice',
    'warranty_pack': 'Warranty pack', 'handover_cert': 'Handover certificate',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comps = ref.watch(truckComponentsProvider(projectId));
    final docs = ref.watch(projectDocsProvider(projectId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(projectDocsProvider(projectId));
          return ref.refresh(truckComponentsProvider(projectId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Text(code ?? 'Record', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            const Text('TRUCK RECORD',
              style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(name ?? 'Digital twin', style: display(27, w: FontWeight.w600)),
            const SizedBox(height: 16),
            comps.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load the record.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) => _content(context, list, docs),
            ),
          ],
        ),
      )),
    );
  }

  Widget _content(BuildContext context, List<TruckComponent> list, AsyncValue<List<ClientDoc>> docs) {
    final active = list.where((c) => c.warrantyState == 'active').length;
    final expiring = list.where((c) => c.warrantyState == 'expiring').length;
    final expired = list.where((c) => c.warrantyState == 'expired').length;

    // group by the stage the part went into (fall back to a bucket)
    final groups = <String, List<TruckComponent>>{};
    for (final c in list) { (groups[c.stageName ?? 'Other / at intake'] ??= []).add(c); }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _summary(list.length, active, expiring, expired),

      if (list.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 8), child: EmptyState(
          icon: Icons.inventory_2_outlined, tint: BT.mint,
          title: 'No components logged yet',
          subtitle: 'Parts appear here as Store logs them and Workshop scans them into the build.'))
      else
        for (final entry in groups.entries) ...[
          SectionLabel('${entry.key} · ${entry.value.length}'),
          ...entry.value.map((c) => _componentCard(context, c)),
        ],

      // The papers that go with the truck.
      const SectionLabel('Documents'),
      docs.when(
        loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(child: SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: BT.mut)))),
        error: (e, _) => AppCard(child: Text('Could not load documents.\n${friendlyError(e)}',
          style: const TextStyle(color: BT.coral, fontSize: 12))),
        data: (ds) => ds.isEmpty
          ? const EmptyState(icon: Icons.description_outlined, tint: BT.sky,
              title: 'No documents yet', subtitle: 'Contract, invoices, warranty pack & handover show here.')
          : AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                for (int i = 0; i < ds.length; i++) Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: Border(
                    bottom: BorderSide(color: i == ds.length - 1 ? Colors.transparent : BT.line))),
                  child: Row(children: [
                    const Icon(Icons.description_rounded, size: 18, color: BT.mut),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_docLabels[ds[i].type] ?? ds[i].type,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                    StatusPill(ds[i].available ? 'Shared' : 'Hidden',
                      color: ds[i].available ? BT.lime : BT.mut2),
                  ]),
                ),
              ])),
      ),
    ]);
  }

  Widget _summary(int total, int active, int expiring, int expired) => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
    decoration: BoxDecoration(
      color: BT.ink, borderRadius: BorderRadius.circular(BT.radiusCard),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 14))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('$total', style: display(46, w: FontWeight.w600, c: Colors.white)),
        const SizedBox(width: 10),
        const Padding(padding: EdgeInsets.only(bottom: 10),
          child: Text('parts\ntracked', style: TextStyle(color: Color(0xFFB4AE9E), fontSize: 13, height: 1.15))),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        _stat('$active', 'In warranty', BT.lime),
        _div(),
        _stat('$expiring', 'Expiring', BT.amber),
        _div(),
        _stat('$expired', 'Expired', BT.coral),
      ]),
    ]),
  );

  Widget _stat(String v, String l, Color c) => Expanded(child: Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(v, style: display(19, w: FontWeight.w600, c: Colors.white)),
      Text(l, style: const TextStyle(color: Color(0xFF918B7C), fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  ]));
  Widget _div() => Container(width: 1, height: 30, color: const Color(0xFF3A3833), margin: const EdgeInsets.symmetric(horizontal: 12));

  Widget _componentCard(BuildContext context, TruckComponent c) {
    final w = _warranty(c.warrantyState);
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.itemName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (c.model != null && c.model!.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(c.model!, style: const TextStyle(color: BT.mut, fontSize: 12)),
            ],
          ])),
          StatusPill(w.label, color: w.color),
        ]),
        const SizedBox(height: 12),
        _kv('Serial', c.serial, mono: true),
        _kv('Vendor', c.vendorName ?? '—'),
        _kv('Fitted', c.installDate == null ? '—'
            : '${_d(c.installDate)}${c.installedByName != null ? ' · ${c.installedByName}' : ''}'),
        if (c.warrantyEnd != null) _kv('Warranty till', _d(c.warrantyEnd)),
        const SizedBox(height: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (c.hasBill) {
              _viewBill(context, c);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: BT.ink, content: Text('No bill was attached at intake for this part.')));
            }
          },
          child: Container(height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.hasBill ? BT.card2 : BT.card,
              borderRadius: BorderRadius.circular(12),
              border: c.hasBill ? null : Border.all(color: BT.line)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(c.hasBill ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
                size: 17, color: c.hasBill ? BT.ink : BT.mut2),
              const SizedBox(width: 8),
              Text(c.hasBill ? 'View bill' : 'No bill on file',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.hasBill ? BT.ink : BT.mut2)),
            ])),
        ),
      ]),
    ));
  }

  void _viewBill(BuildContext context, TruckComponent c) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white,
        title: Text('Bill · ${c.serial}', style: const TextStyle(fontSize: 15))),
      body: Center(child: InteractiveViewer(
        child: Image.network(c.billUrl!, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('Could not load bill',
            style: TextStyle(color: Colors.white70))))),
    )));
  }

  Widget _kv(String k, String v, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 96, child: Text(k, style: const TextStyle(fontSize: 12.5, color: BT.mut))),
      Expanded(child: Text(v, style: TextStyle(fontSize: 13,
        fontWeight: FontWeight.w600, color: BT.ink,
        fontFeatures: mono ? const [] : null))),
    ]),
  );
}

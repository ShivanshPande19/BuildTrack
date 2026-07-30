import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Component detail (st6) — digital record + warranty + recall check.
class ComponentDetailScreen extends StatelessWidget {
  final ComponentRow component;
  const ComponentDetailScreen({super.key, required this.component});

  static final _fmt = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final c = component;
    return Scaffold(
      body: SafeArea(child: ListView(
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
            if (c.projectCode != null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
              child: Text(c.projectCode!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
          ]),
          const SizedBox(height: 14),
          Text(c.model.isEmpty ? c.name : c.model, style: display(27, w: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${c.name} · digital record', style: const TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 16),

          AppCard(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6), child: Column(children: [
            _kv('Model', c.model.isEmpty ? '—' : c.model),
            _kv('Serial', c.serial),
            _kv('Vendor', c.vendorName ?? '—'),
            _kv('Installed in', c.projectCode == null ? 'In store' : '${c.projectCode} · ${c.installDate == null ? '' : _fmt.format(c.installDate!)}'),
            _kv('Status', c.status),
          ])),

          const SizedBox(height: 12),
          // warranty banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.warrantyActive ? BT.lime : BT.card2,
              borderRadius: BorderRadius.circular(BT.radiusCard),
              border: Border.all(color: c.warrantyActive ? Colors.transparent : BT.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(c.warrantyEnd == null ? 'NO WARRANTY ON RECORD' : (c.warrantyActive ? 'WARRANTY ACTIVE' : 'WARRANTY EXPIRED'),
                  style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600,
                    color: c.warrantyActive ? const Color(0xFF3A4A12) : BT.mut)),
                if (c.warrantyEnd != null) StatusPill(c.warrantyActive ? 'Active' : 'Expired',
                  color: c.warrantyActive ? BT.ink : BT.coral, dark: c.warrantyActive),
              ]),
              const SizedBox(height: 8),
              Text(c.warrantyEnd == null ? 'Add a bill/warranty at intake' : 'Valid till ${_fmt.format(c.warrantyEnd!)}',
                style: display(18, w: FontWeight.w600)),
            ]),
          ),

          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _btn(context, 'Bill', Icons.description_outlined, false, () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Bill viewer — coming soon')));
            })),
            const SizedBox(width: 11),
            Expanded(flex: 1, child: _btn(context, 'Recall check', Icons.warning_amber_rounded, true, () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                RecallCheckScreen(itemCatalogId: c.itemCatalogId, name: c.name, model: c.model)));
            })),
          ]),
        ],
      )),
    );
  }

  Widget _kv(String k, String v) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(fontSize: 13, color: BT.mut)),
      Flexible(child: Text(v, textAlign: TextAlign.right, style: display(14, w: FontWeight.w600))),
    ]),
  );

  Widget _btn(BuildContext context, String label, IconData icon, bool dark, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(height: 52, alignment: Alignment.center,
      decoration: BoxDecoration(color: dark ? BT.ink : BT.card, borderRadius: BorderRadius.circular(16),
        border: dark ? null : Border.all(color: BT.line)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: dark ? BT.lime : BT.ink),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: dark ? Colors.white : BT.ink)),
      ])),
  );
}

/// Recall check (st7) — every truck with this model installed (Hero #2).
class RecallCheckScreen extends ConsumerWidget {
  final String itemCatalogId, name, model;
  const RecallCheckScreen({super.key, required this.itemCatalogId, required this.name, required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recall = ref.watch(recallProvider(itemCatalogId));
    return Scaffold(
      body: SafeArea(child: ListView(
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
            const StatusPill('Recall', color: BT.coral),
          ]),
          const SizedBox(height: 14),
          Text('Recall check', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 14),
          recall.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 50),
              child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not run recall.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: (rows) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFFFCEAE2), Color(0xFFFBF6F2)]),
                    borderRadius: BorderRadius.circular(BT.radiusCard), border: Border.all(color: const Color(0xFFF3D8CC))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AFFECTED MODEL',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: BT.mut, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(model.isEmpty ? name : '$name · $model', style: display(18, w: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${rows.length}', style: display(38, w: FontWeight.w600)),
                      const SizedBox(width: 8),
                      const Padding(padding: EdgeInsets.only(bottom: 6),
                        child: Text('trucks affected', style: TextStyle(color: BT.mut, fontSize: 13))),
                    ]),
                  ]),
                ),
                const SectionLabel('Affected trucks'),
                if (rows.isEmpty)
                  const EmptyState(icon: Icons.verified_outlined, tint: BT.lime,
                    title: 'None installed', subtitle: 'This model is not installed in any truck yet.')
                else ...[
                  ...rows.map((r) => Padding(padding: const EdgeInsets.only(bottom: 11),
                    child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.projectCode ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('Serial ${r.serial ?? '—'} · ${r.status ?? ''}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                      ])),
                      StatusPill(r.status == 'installed' ? 'Notify' : (r.status ?? ''),
                        color: r.status == 'faulty' ? BT.coral : BT.amber),
                    ])))),
                  const SizedBox(height: 6),
                  // Actually sends it: each affected build's PM and client get a
                  // notification. This button used to only show a snackbar.
                  PrimaryButton('Notify all ${rows.length}', icon: Icons.notifications_active_rounded,
                    bg: BT.ink, fg: BT.card, onTap: () async {
                      try {
                        final n = await ref.read(storeRepoProvider)
                            .recallNotify(itemCatalogId, note: 'Safety check required on this part.');
                        ref.invalidate(notificationsProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor: BT.ink,
                            content: Text(n == 0
                              ? 'No trucks to notify.'
                              : 'Recall notice sent for $n truck(s) — PMs and clients told.')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor: BT.coral, content: Text(friendlyError(e))));
                        }
                      }
                    }),
                ],
              ]);
            },
          ),
        ],
      )),
    );
  }
}

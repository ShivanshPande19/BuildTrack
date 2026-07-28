import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'raise_request.dart';
import 'approve_design.dart';

/// Client — everything about ONE truck in a single screen:
/// progress + current stage + build journey + photos + documents + raise request.
class ClientTruckDetail extends ConsumerWidget {
  final Project project;
  const ClientTruckDetail({super.key, required this.project});

  static final _fmt = DateFormat('d MMM');

  ({String label, Color color}) _status(String s) => switch (s) {
    'on_track' => (label: 'On track', color: BT.lime),
    'at_risk'  => (label: 'At-risk', color: BT.amber),
    'delayed'  => (label: 'Delayed', color: BT.coral),
    'delivered'=> (label: 'Delivered', color: BT.ink),
    _          => (label: s, color: BT.mut2),
  };

  static const _docLabel = {
    'contract': 'Contract', 'invoice': 'Invoice', 'warranty_pack': 'Warranty pack', 'handover_cert': 'Handover certificate',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(projectDetailProvider(project.id));
    final photos = ref.watch(truckPhotosProvider(project.id)).valueOrNull ?? [];
    final docs = ref.watch(truckDocsProvider(project.id)).valueOrNull ?? [];
    final designs = ref.watch(truckDesignsProvider(project.id)).valueOrNull ?? [];
    final pending = designs.where((d) => d.status == 'pending_approval').toList();
    final s = _status(project.status);

    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(truckPhotosProvider(project.id));
          ref.invalidate(truckDocsProvider(project.id));
          ref.invalidate(truckDesignsProvider(project.id));
          return ref.refresh(projectDetailProvider(project.id).future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 30), children: [
          // header
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
            StatusPill(s.label, color: s.color, dark: project.status == 'delivered'),
          ]),
          const SizedBox(height: 14),
          Text(project.name, style: display(27, w: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(project.code, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 16),

          detail.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: (d) {
              final cur = d.currentStage;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // progress ring
                AppCard(padding: const EdgeInsets.all(20), child: Column(children: [
                  SizedBox(width: 148, height: 148, child: Stack(alignment: Alignment.center, children: [
                    SizedBox(width: 130, height: 130, child: CircularProgressIndicator(
                      value: d.project.progressPct.clamp(0, 100) / 100, strokeWidth: 12, backgroundColor: BT.track, valueColor: const AlwaysStoppedAnimation(BT.lime))),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${d.project.progressPct}%', style: display(30, w: FontWeight.w600)),
                      const Text('BUILT', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: BT.mut, fontWeight: FontWeight.w600)),
                    ]),
                  ])),
                  const SizedBox(height: 8),
                  Text('Currently: ${cur?.name ?? '—'}', style: const TextStyle(color: BT.mut, fontSize: 13)),
                  const SizedBox(height: 10),
                  StatusPill('Delivery ${d.targetDelivery == null ? '—' : _fmt.format(d.targetDelivery!)}', color: BT.lime),
                ])),

                // design approval
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...pending.map((dz) => Padding(padding: const EdgeInsets.only(bottom: 10), child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApproveDesign(design: dz, projectId: project.id))),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFBE9F1), Color(0xFFFBFAF5)]),
                        borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF2D3E1))),
                      child: Row(children: [
                        Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: BT.pink, borderRadius: BorderRadius.circular(13)),
                          child: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF4A2438))),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Approve ${dz.type} design', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 2), const Text('Waiting for you', style: TextStyle(color: BT.mut, fontSize: 12)),
                        ])),
                        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                      ]),
                    ),
                  ))),
                ],

                // build journey
                const SectionLabel('Build journey'),
                if (d.stages.isEmpty)
                  const EmptyState(icon: Icons.timeline_rounded, tint: BT.sky, title: 'Not started', subtitle: 'Your build stages will appear here.')
                else
                  ...List.generate(d.stages.length, (i) => _tl(d.stages[i], i == d.stages.length - 1)),
              ]);
            },
          ),

          // photos
          const SectionLabel('Photos'),
          if (photos.isEmpty)
            const EmptyState(icon: Icons.photo_library_outlined, tint: BT.sky, title: 'No photos yet', subtitle: 'The workshop posts progress photos as your build moves along.')
          else
            SizedBox(height: 150, child: ListView.separated(
              scrollDirection: Axis.horizontal, itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: 200, child: Stack(fit: StackFit.expand, children: [
                Container(color: BT.card2),
                Image.network(photos[i].url, fit: BoxFit.cover,
                  loadingBuilder: (c, w, prog) => prog == null ? w : const Center(child: CircularProgressIndicator(color: BT.mut2, strokeWidth: 2)),
                  errorBuilder: (c, e, st) => const Center(child: Icon(Icons.image_not_supported_outlined, color: BT.mut2))),
                if (photos[i].caption != null) Positioned(left: 0, right: 0, bottom: 0, child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])),
                  child: Text(photos[i].caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)))),
              ]))),
            )),

          // documents
          const SectionLabel('Documents'),
          if (docs.isEmpty)
            const EmptyState(icon: Icons.description_outlined, tint: BT.lav, title: 'No documents yet', subtitle: 'Contract, invoices and warranty pack will show here.')
          else
            ...docs.map((doc) => Padding(padding: const EdgeInsets.only(bottom: 11),
              child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                Container(width: 46, height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.description_rounded, size: 21, color: BT.ink)),
                const SizedBox(width: 13),
                Expanded(child: Text(_docLabel[doc.type] ?? doc.type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                doc.available
                  ? GestureDetector(behavior: HitTestBehavior.opaque,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Opening document…'))),
                      child: const Icon(Icons.download_rounded, size: 22, color: BT.mut))
                  : const StatusPill('Soon', color: BT.amber),
              ]))),
            ),

          const SizedBox(height: 18),
          PrimaryButton('Raise a request', icon: Icons.headset_mic_rounded, bg: BT.ink, fg: BT.card,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaiseRequest(projectId: project.id)))),
        ]),
      )),
    );
  }

  Widget _tl(Stage s, bool isLast) {
    final done = s.status == 'done';
    final now = s.status == 'in_progress';
    final sub = switch (s.status) {
      'done'        => 'Done ${s.actualEnd == null ? '' : _fmt.format(s.actualEnd!)}',
      'in_progress' => 'In progress now',
      _             => 'Coming ${s.plannedStart == null ? 'soon' : _fmt.format(s.plannedStart!)}',
    };
    Widget dot;
    if (done) {
      dot = Container(width: 22, height: 22, alignment: Alignment.center, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 13, color: BT.ink));
    } else if (now) {
      dot = Container(width: 22, height: 22, alignment: Alignment.center, decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle), child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
    } else {
      dot = Container(width: 22, height: 22, decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 1.5)));
    }
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(children: [dot, if (!isLast) Expanded(child: Container(width: 2, color: BT.line, margin: const EdgeInsets.symmetric(vertical: 2)))]),
      const SizedBox(width: 14),
      Expanded(child: Padding(padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 1), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.name, style: TextStyle(fontSize: 15, fontWeight: (done || now) ? FontWeight.w600 : FontWeight.w500, color: (done || now) ? BT.ink : BT.mut2)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 11.5, color: BT.mut)),
      ]))),
    ]));
  }
}

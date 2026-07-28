import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'raise_request.dart';
import 'approve_design.dart';
import 'client_stage.dart';

/// Client — one truck: progress + current stage + build journey (tap a stage for
/// its photos) + documents. Everything about the truck in one clean screen.
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
    final docs = ref.watch(truckDocsProvider(project.id)).valueOrNull ?? [];
    final designs = ref.watch(truckDesignsProvider(project.id)).valueOrNull ?? [];
    final pending = designs.where((d) => d.status == 'pending_approval').toList();
    final s = _status(project.status);

    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(truckDocsProvider(project.id));
          ref.invalidate(truckDesignsProvider(project.id));
          return ref.refresh(projectDetailProvider(project.id).future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 30), children: [
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
          Text(project.name, style: display(26, w: FontWeight.w600)),
          Text(project.code, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 16),

          detail.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: (d) {
              final cur = d.currentStage;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // compact progress card (ring + info, no empty sides)
                AppCard(padding: const EdgeInsets.all(18), child: Row(children: [
                  SizedBox(width: 88, height: 88, child: Stack(alignment: Alignment.center, children: [
                    SizedBox(width: 88, height: 88, child: CircularProgressIndicator(
                      value: d.project.progressPct.clamp(0, 100) / 100, strokeWidth: 9,
                      backgroundColor: BT.track, valueColor: const AlwaysStoppedAnimation(BT.lime))),
                    Text('${d.project.progressPct}%', style: display(20, w: FontWeight.w600)),
                  ])),
                  const SizedBox(width: 18),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('CURRENTLY', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, color: BT.mut, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(cur?.name ?? 'Getting started', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.event_rounded, size: 15, color: BT.mut),
                      const SizedBox(width: 6),
                      Text('Delivery ${d.targetDelivery == null ? '—' : _fmt.format(d.targetDelivery!)}',
                        style: const TextStyle(fontSize: 12.5, color: BT.mut, fontWeight: FontWeight.w600)),
                    ]),
                  ])),
                ])),

                // design approval CTA
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...pending.map((dz) => Padding(padding: const EdgeInsets.only(bottom: 10), child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApproveDesign(design: dz, projectId: project.id))),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFBE9F1), Color(0xFFFBFAF5)]),
                        borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF2D3E1))),
                      child: Row(children: [
                        Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: BT.pink, borderRadius: BorderRadius.circular(13)),
                          child: const Icon(Icons.edit_rounded, size: 19, color: Color(0xFF4A2438))),
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

                const SectionLabel('Build journey'),
                const Padding(padding: EdgeInsets.only(left: 2, bottom: 10),
                  child: Text('Tap a stage to see its photos', style: TextStyle(color: BT.mut, fontSize: 12))),
                if (d.stages.isEmpty)
                  const EmptyState(icon: Icons.timeline_rounded, tint: BT.sky, title: 'Not started', subtitle: 'Your build stages will appear here.')
                else
                  ...List.generate(d.stages.length, (i) => _stageTile(context, d.stages[i], i == d.stages.length - 1)),
              ]);
            },
          ),

          // documents — only when there are any (no empty card / dead space)
          if (docs.isNotEmpty) ...[
            const SectionLabel('Documents'),
            ...docs.map((doc) => Padding(padding: const EdgeInsets.only(bottom: 11),
              child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.description_rounded, size: 20, color: BT.ink)),
                const SizedBox(width: 13),
                Expanded(child: Text(_docLabel[doc.type] ?? doc.type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                doc.available
                  ? GestureDetector(behavior: HitTestBehavior.opaque,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Opening document…'))),
                      child: const Icon(Icons.download_rounded, size: 22, color: BT.mut))
                  : const StatusPill('Soon', color: BT.amber),
              ]))),
            ),
          ],

          const SizedBox(height: 18),
          PrimaryButton('Raise a request', icon: Icons.headset_mic_rounded, bg: BT.ink, fg: BT.card,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaiseRequest(projectId: project.id)))),
        ]),
      )),
    );
  }

  Widget _stageTile(BuildContext context, Stage s, bool isLast) {
    final done = s.status == 'done';
    final now = s.status == 'in_progress';
    final sub = switch (s.status) {
      'done'        => 'Done ${s.actualEnd == null ? '' : _fmt.format(s.actualEnd!)}',
      'in_progress' => 'In progress now',
      _             => 'Coming ${s.plannedStart == null ? 'soon' : _fmt.format(s.plannedStart!)}',
    };
    Widget dot;
    if (done) {
      dot = Container(width: 24, height: 24, alignment: Alignment.center, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 14, color: BT.ink));
    } else if (now) {
      dot = Container(width: 24, height: 24, alignment: Alignment.center, decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle), child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
    } else {
      dot = Container(width: 24, height: 24, decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 1.5)));
    }
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(children: [dot, if (!isLast) Expanded(child: Container(width: 2, color: BT.line, margin: const EdgeInsets.symmetric(vertical: 3)))]),
      const SizedBox(width: 13),
      Expanded(child: Padding(padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientStageDetail(stage: s))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: TextStyle(fontSize: 14.5, fontWeight: (done || now) ? FontWeight.w600 : FontWeight.w500, color: (done || now) ? BT.ink : BT.mut)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 11.5, color: BT.mut)),
              ])),
              Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.photo_library_outlined, size: 16, color: BT.mut2),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: BT.mut2),
              ]),
            ]),
          ),
        ),
      )),
    ]));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'raise_request.dart';
import 'approve_design.dart';

/// Client — one truck, tabbed: Progress · Photos · Docs · Support.
class TruckView extends ConsumerStatefulWidget {
  final Project project;
  const TruckView({super.key, required this.project});
  @override
  ConsumerState<TruckView> createState() => _TruckViewState();
}

class _TruckViewState extends ConsumerState<TruckView> {
  int _tab = 0;
  static const _labels = ['Progress', 'Photos', 'Docs', 'Support'];
  static final _fmt = DateFormat('d MMM');

  String get _pid => widget.project.id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(children: [
        // top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(20, w: FontWeight.w600)),
              Text(widget.project.code, style: const TextStyle(color: BT.mut, fontSize: 12)),
            ])),
          ]),
        ),
        Expanded(child: IndexedStack(index: _tab, children: [
          _progressTab(), _photosTab(), _docsTab(), _supportTab(),
        ])),
      ])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.timeline_rounded, Icons.photo_library_rounded, Icons.description_rounded, Icons.headset_mic_rounded],
        active: _tab, activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaiseRequest(projectId: _pid))),
      ),
    );
  }

  // ── PROGRESS ──────────────────────────────────────────────
  Widget _progressTab() {
    final detail = ref.watch(projectDetailProvider(_pid));
    final designs = ref.watch(truckDesignsProvider(_pid)).valueOrNull ?? [];
    final pending = designs.where((d) => d.status == 'pending_approval').toList();
    return RefreshIndicator(
      onRefresh: () async { ref.invalidate(truckDesignsProvider(_pid)); return ref.refresh(projectDetailProvider(_pid).future); },
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator(color: BT.ink)),
        error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [
          AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13)))]),
        data: (d) {
          final cur = d.currentStage;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
            // progress ring card
            AppCard(padding: const EdgeInsets.all(20), child: Column(children: [
              SizedBox(width: 150, height: 150, child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 132, height: 132, child: CircularProgressIndicator(
                  value: d.project.progressPct.clamp(0, 100) / 100, strokeWidth: 12,
                  backgroundColor: BT.track, valueColor: const AlwaysStoppedAnimation(BT.lime))),
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

            // design approval CTA
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...pending.map((dz) => Padding(padding: const EdgeInsets.only(bottom: 10), child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApproveDesign(design: dz, projectId: _pid))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFBE9F1), Color(0xFFFBFAF5)]),
                    borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF2D3E1))),
                  child: Row(children: [
                    Container(width: 44, height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(color: BT.pink, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF4A2438))),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Approve ${dz.type} design', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      const Text('Waiting for you', style: TextStyle(color: BT.mut, fontSize: 12)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
                  ]),
                ),
              ))),
            ],

            const SectionLabel('Build journey'),
            if (d.stages.isEmpty)
              const EmptyState(icon: Icons.timeline_rounded, tint: BT.sky, title: 'Not started', subtitle: 'Your build stages will appear here.')
            else
              ...List.generate(d.stages.length, (i) => _tl(d.stages[i], i == d.stages.length - 1)),
          ]);
        },
      ),
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
      dot = Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 13, color: BT.ink));
    } else if (now) {
      dot = Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle),
        child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)));
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

  // ── PHOTOS ────────────────────────────────────────────────
  Widget _photosTab() {
    final photos = ref.watch(truckPhotosProvider(_pid));
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(truckPhotosProvider(_pid).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        const SectionLabel('Updates from your build'),
        photos.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load photos.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.photo_library_outlined, tint: BT.sky, title: 'No photos yet', subtitle: 'The workshop posts progress photos as your build moves along.')
            : GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82,
                children: list.map((p) => ClipRRect(borderRadius: BorderRadius.circular(16), child: Stack(fit: StackFit.expand, children: [
                  Container(color: BT.card2),
                  Image.network(p.url, fit: BoxFit.cover,
                    loadingBuilder: (c, w, prog) => prog == null ? w : const Center(child: CircularProgressIndicator(color: BT.mut2, strokeWidth: 2)),
                    errorBuilder: (c, e, s) => const Center(child: Icon(Icons.image_not_supported_outlined, color: BT.mut2))),
                  if (p.caption != null) Positioned(left: 0, right: 0, bottom: 0, child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])),
                    child: Text(p.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)))),
                ]))).toList()),
        ),
      ]),
    );
  }

  // ── DOCS ──────────────────────────────────────────────────
  static const _docLabel = {
    'contract': 'Contract', 'invoice': 'Invoice', 'warranty_pack': 'Warranty pack', 'handover_cert': 'Handover certificate',
  };
  Widget _docsTab() {
    final docs = ref.watch(truckDocsProvider(_pid));
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(truckDocsProvider(_pid).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        const SectionLabel('Your documents'),
        docs.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load documents.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.description_outlined, tint: BT.lav, title: 'No documents yet', subtitle: 'Contract, invoices and warranty pack will show here.')
            : Column(children: list.map((doc) => Padding(padding: const EdgeInsets.only(bottom: 11),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                  Container(width: 46, height: 46, alignment: Alignment.center,
                    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.description_rounded, size: 21, color: BT.ink)),
                  const SizedBox(width: 13),
                  Expanded(child: Text(_docLabel[doc.type] ?? doc.type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  doc.available
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Opening document…'))),
                        child: const Icon(Icons.download_rounded, size: 22, color: BT.mut))
                    : const StatusPill('Soon', color: BT.amber),
                ])))).toList()),
        ),
      ]),
    );
  }

  // ── SUPPORT ───────────────────────────────────────────────
  ({String label, Color color}) _ticketPill(String s) => switch (s) {
    'resolved' => (label: 'Resolved', color: BT.lime),
    'closed'   => (label: 'Closed', color: BT.mut2),
    'in_progress' => (label: 'In review', color: BT.amber),
    _          => (label: 'Open', color: BT.sky),
  };
  Widget _supportTab() {
    final tickets = ref.watch(myTicketsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myTicketsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        const SectionLabel('Help'),
        AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
          Container(width: 46, height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: BT.ink)),
          const SizedBox(width: 13),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Raise a request', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(height: 2),
            Text('Tap + below · we reply fast', style: TextStyle(color: BT.mut, fontSize: 12)),
          ])),
        ])),
        const SectionLabel('Your requests'),
        tickets.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.headset_mic_outlined, tint: BT.lime, title: 'No requests', subtitle: 'Anything you raise shows here with its status.')
            : Column(children: list.map((t) => Padding(padding: const EdgeInsets.only(bottom: 11),
                child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.description == null || t.description!.isEmpty ? t.category : t.description!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('#${t.number} · ${t.category}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
                  ])),
                  StatusPill(_ticketPill(t.status).label, color: _ticketPill(t.status).color),
                ])))).toList()),
        ),
      ]),
    );
  }
}

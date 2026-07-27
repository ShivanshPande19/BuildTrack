import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Everything about one build stage of a truck: photos, installed parts
/// (traceability), checklist and any logged delays. Visible to admin/PM.
class StageDetailScreen extends ConsumerWidget {
  final Stage stage;
  final String? projectCode;
  const StageDetailScreen({super.key, required this.stage, this.projectCode});

  static final _fmt = DateFormat('d MMM');
  static final _fmtY = DateFormat('d MMM yyyy');
  String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  ({String label, Color color}) _statusPill(String s) => switch (s) {
    'done'        => (label: 'Done', color: BT.lime),
    'in_progress' => (label: 'In progress', color: BT.sky),
    'rework'      => (label: 'Rework', color: BT.coral),
    _             => (label: 'To do', color: BT.mut2),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(stageBundleProvider(stage.id));
    final s = _statusPill(stage.status);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(stageBundleProvider(stage.id).future),
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
              StatusPill(s.label, color: s.color),
            ]),
            const SizedBox(height: 14),
            if (projectCode != null)
              Text(projectCode!, style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(stage.name, style: display(27, w: FontWeight.w600)),
            const SizedBox(height: 14),

            // meta card: dates + assignee
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _metaRow('Planned', '${_d(stage.plannedStart)} → ${_d(stage.plannedEnd)}'),
                const SizedBox(height: 10),
                _metaRow('Actual', '${_d(stage.actualStart)} → ${_d(stage.actualEnd)}'),
                bundle.maybeWhen(
                  data: (b) => b.assignee == null ? const SizedBox.shrink()
                    : Padding(padding: const EdgeInsets.only(top: 10), child: _metaRow('Assignee', b.assignee!)),
                  orElse: () => const SizedBox.shrink()),
              ]),
            ),

            bundle.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 16),
                child: AppCard(child: Text('Could not load stage details.\n$e',
                  style: const TextStyle(color: BT.coral, fontSize: 13)))),
              data: (b) => _body(b),
            ),
          ],
        ),
      )),
    );
  }

  Widget _metaRow(String k, String v) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(k, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
    Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
  ]);

  Widget _body(StageBundle b) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // delay banner
    if (b.delays.isNotEmpty) ...[
      const SizedBox(height: 14),
      ...b.delays.map((d) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: BT.coral, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(
            'Delayed ${d.days}d · ${d.reason}${d.note != null ? ' — ${d.note}' : ''}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A2E18), fontWeight: FontWeight.w500))),
        ]),
      )),
    ],

    // photos
    const SectionLabel('Photos'),
    if (b.photos.isEmpty)
      _emptyNote('No photos uploaded for this stage yet.')
    else
      SizedBox(height: 172, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: b.photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _photoCard(b.photos[i]),
      )),

    // installed parts
    const SectionLabel('Parts installed'),
    if (b.parts.isEmpty)
      _emptyNote('No components logged against this stage yet.')
    else
      ...b.parts.map(_partCard),

    // checklist
    const SectionLabel('Checklist'),
    if (b.checklist.isEmpty)
      _emptyNote('No checklist items.')
    else
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: b.checklist.map(_checkRow).toList()),
      ),
  ]);

  Widget _emptyNote(String t) => AppCard(child: Text(t, style: const TextStyle(color: BT.mut, fontSize: 13)));

  Widget _photoCard(StagePhoto p) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(width: 232, child: Stack(fit: StackFit.expand, children: [
      Container(color: BT.card2),
      Image.network(p.url, fit: BoxFit.cover,
        loadingBuilder: (c, w, prog) => prog == null ? w
          : const Center(child: CircularProgressIndicator(color: BT.mut2, strokeWidth: 2)),
        errorBuilder: (c, e, s) => const Center(child: Icon(Icons.image_not_supported_outlined, color: BT.mut2, size: 30))),
      if (p.caption != null) Positioned(left: 0, right: 0, bottom: 0, child: Container(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)])),
        child: Text(p.caption!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
    ])),
  );

  Widget _partCard(StagePart p) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.model.isEmpty ? p.name : '${p.name} · ${p.model}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
          StatusPill(p.status, color: p.status == 'faulty' ? BT.coral : BT.mint),
        ]),
        const SizedBox(height: 8),
        _kv('Serial', p.serial),
        _kv('Vendor', p.vendor),
        _kv('Warranty till', p.warrantyEnd == null ? '—' : _fmtY.format(p.warrantyEnd!)),
      ]),
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(children: [
      SizedBox(width: 96, child: Text(k, style: const TextStyle(color: BT.mut, fontSize: 12.5))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _checkRow(ChecklistItem c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(children: [
      Container(width: 22, height: 22, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.done ? BT.lime : Colors.transparent, shape: BoxShape.circle,
          border: c.done ? null : Border.all(color: BT.mut2, width: 1.5)),
        child: c.done ? const Icon(Icons.check_rounded, size: 13, color: BT.ink) : null),
      const SizedBox(width: 12),
      Expanded(child: Text(c.label, style: TextStyle(fontSize: 14,
        color: c.done ? BT.ink : BT.mut,
        decoration: c.done ? TextDecoration.lineThrough : null,
        decorationColor: BT.mut2))),
    ]),
  );
}

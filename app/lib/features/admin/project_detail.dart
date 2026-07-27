import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'stage_detail.dart';

/// Admin — Project detail (a4): progress, delivery date and the build-stage timeline.
class ProjectDetailScreen extends ConsumerWidget {
  final String projectId;
  final Project? initial; // for an instant header while stages load
  const ProjectDetailScreen({super.key, required this.projectId, this.initial});

  static final _fmt = DateFormat('d MMM');
  String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  ({String label, Color color}) _status(String s) => switch (s) {
    'on_track' => (label: 'On-track', color: BT.lime),
    'at_risk'  => (label: 'At-risk', color: BT.amber),
    'delayed'  => (label: 'Delayed', color: BT.coral),
    'delivered'=> (label: 'Delivered', color: BT.mint),
    _          => (label: s, color: BT.mut2),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(projectDetailProvider(projectId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(projectDetailProvider(projectId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            // top row: back + code pill
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              if (initial != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Text(initial!.code, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
            ]),
            const SizedBox(height: 14),
            detail.when(
              loading: () => _headerFromInitial(),
              error: (e, _) => AppCard(child: Text('Could not load project.\n$e',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (d) => _content(context, d),
            ),
          ],
        ),
      )),
    );
  }

  Widget _headerFromInitial() => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Center(child: Column(children: [
      if (initial != null) Text(initial!.name, style: display(24, w: FontWeight.w600)),
      const SizedBox(height: 24),
      const CircularProgressIndicator(color: BT.ink),
    ])),
  );

  Widget _content(BuildContext context, ProjectDetailData d) {
    final s = _status(d.project.status);
    final cur = d.currentStage;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // title + status
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(d.project.name, style: display(27, w: FontWeight.w600))),
        const SizedBox(width: 10),
        StatusPill(s.label, color: s.color),
      ]),
      const SizedBox(height: 16),

      // progress + delivery card
      AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${d.project.progressPct}', style: display(46, w: FontWeight.w600)),
              Text('%', style: display(22, w: FontWeight.w600, c: BT.mut)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Delivery', style: TextStyle(color: BT.mut, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(_d(d.targetDelivery), style: display(16, w: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 14),
          _track(cur?.name ?? 'Overall', d.project.progressPct, s.color),
        ]),
      ),

      const SectionLabel('Build stages'),
      if (d.stages.isEmpty)
        const AppCard(child: Text('No stages yet.', style: TextStyle(color: BT.mut, fontSize: 13)))
      else
        ...List.generate(d.stages.length,
          (i) => _timelineTile(context, d.stages[i], i == d.stages.length - 1, d.project.code)),
    ]);
  }

  // progress track: textured-free bar with a floating % pill.
  Widget _track(String label, int pct, Color pill) {
    final band = (0.34 + (pct / 100).clamp(0.0, 1.0) * 0.55).clamp(0.34, 0.93);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(height: 44, child: Stack(children: [
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(color: BT.track, borderRadius: BorderRadius.circular(999)))),
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis)))),
        Positioned.fill(child: Align(alignment: Alignment(band.toDouble() * 2 - 1, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: pill, borderRadius: BorderRadius.circular(999),
              boxShadow: const [BoxShadow(color: Color(0x1A695228), blurRadius: 8, offset: Offset(0, 3))]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: BT.ink, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text('$pct%', style: display(13, w: FontWeight.w600)),
            ])))),
      ])),
    );
  }

  Widget _timelineTile(BuildContext context, Stage s, bool isLast, String code) {
    final done = s.status == 'done';
    final now = s.status == 'in_progress';
    final todo = s.status == 'todo';

    final subtitle = switch (s.status) {
      'done'        => 'Completed ${_d(s.actualEnd ?? s.plannedEnd)}',
      'in_progress' => 'In progress',
      'rework'      => 'Rework needed',
      _             => 'Starts ${_d(s.plannedStart)}',
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
      dot = Container(width: 22, height: 22,
        decoration: BoxDecoration(color: BT.card2, shape: BoxShape.circle, border: Border.all(color: BT.line, width: 1.5)));
    }

    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(children: [
        dot,
        if (!isLast) Expanded(child: Container(width: 2, color: BT.line,
          margin: const EdgeInsets.symmetric(vertical: 2))),
      ]),
      const SizedBox(width: 14),
      Expanded(child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, style: TextStyle(fontSize: 15,
            fontWeight: todo ? FontWeight.w500 : FontWeight.w600,
            color: todo ? BT.mut2 : BT.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: BT.mut)),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StageDetailScreen(stage: s, projectCode: code))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BT.ink)),
                SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, size: 16, color: BT.ink),
              ]),
            ),
          ),
        ]),
      )),
    ]));
  }
}

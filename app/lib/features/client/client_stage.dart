import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Client — one build stage: its status + the photos uploaded for it.
class ClientStageDetail extends ConsumerWidget {
  final Stage stage;
  const ClientStageDetail({super.key, required this.stage});

  static final _fmt = DateFormat('d MMM yyyy');

  ({String label, Color color}) _pill() => switch (stage.status) {
    'done'        => (label: 'Completed', color: BT.lime),
    'in_progress' => (label: 'In progress', color: BT.amber),
    'rework'      => (label: 'Being reworked', color: BT.coral),
    _             => (label: 'Coming up', color: BT.sky),
  };

  String get _when => switch (stage.status) {
    'done'        => 'Completed ${stage.actualEnd == null ? '' : _fmt.format(stage.actualEnd!)}',
    'in_progress' => 'In progress now',
    _             => stage.plannedStart == null ? 'Scheduled soon' : 'Planned for ${_fmt.format(stage.plannedStart!)}',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(stagePhotosProvider(stage.id));
    final p = _pill();
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(stagePhotosProvider(stage.id).future),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 30), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
            StatusPill(p.label, color: p.color),
          ]),
          const SizedBox(height: 14),
          Text(stage.name, style: display(27, w: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_when, style: const TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 18),
          photos.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not load photos.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: (list) => list.isEmpty
              ? EmptyState(
                  icon: stage.status == 'todo' ? Icons.schedule_rounded : Icons.photo_library_outlined,
                  tint: BT.sky,
                  title: stage.status == 'todo' ? 'Not started yet' : 'No photos yet',
                  subtitle: stage.status == 'todo'
                    ? 'Photos will appear here once work on this stage begins.'
                    : 'The team will post photos as this stage progresses.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${list.length} photo${list.length == 1 ? '' : 's'}', style: const TextStyle(color: BT.mut, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82,
                    children: list.map((ph) => ClipRRect(borderRadius: BorderRadius.circular(16), child: Stack(fit: StackFit.expand, children: [
                      Container(color: BT.card2),
                      Image.network(ph.url, fit: BoxFit.cover,
                        loadingBuilder: (c, w, prog) => prog == null ? w : const Center(child: CircularProgressIndicator(color: BT.mut2, strokeWidth: 2)),
                        errorBuilder: (c, e, s) => const Center(child: Icon(Icons.image_not_supported_outlined, color: BT.mut2))),
                      if (ph.caption != null) Positioned(left: 0, right: 0, bottom: 0, child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])),
                        child: Text(ph.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)))),
                    ]))).toList(),
                  ),
                ]),
          ),
        ]),
      )),
    );
  }
}

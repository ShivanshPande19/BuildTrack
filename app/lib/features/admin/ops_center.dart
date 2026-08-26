import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'project_dossier.dart';

/// Admin — the operations command center.
///
/// The owner's single, live view of the whole floor: how many builds are
/// active, which department (and team) is working on each, which stage it sits
/// at and for how long, and what needs attention right now. No walking the
/// floor asking "which build is where, who's on it".
class OpsCenterScreen extends ConsumerStatefulWidget {
  const OpsCenterScreen({super.key});
  @override
  ConsumerState<OpsCenterScreen> createState() => _OpsCenterScreenState();
}

class _OpsCenterScreenState extends ConsumerState<OpsCenterScreen> {
  String? _dept; // department filter (current_discipline); null = all

  static final _fmt = DateFormat('d MMM');

  // department → label · icon · accent
  static const _depts = ['workshop', 'design', 'store', 'procurement', 'service'];
  ({String label, IconData icon}) _dept_(String d) => switch (d) {
    'workshop'    => (label: 'Workshop', icon: Icons.handyman_rounded),
    'design'      => (label: 'Design', icon: Icons.brush_rounded),
    'store'       => (label: 'Store', icon: Icons.inventory_2_rounded),
    'procurement' => (label: 'Procurement', icon: Icons.shopping_cart_rounded),
    'service'     => (label: 'Service', icon: Icons.build_rounded),
    _             => (label: d, icon: Icons.category_rounded),
  };

  ({String label, Color color}) _statusPill(String s) => switch (s) {
    'on_track'  => (label: 'On-track', color: BT.lime),
    'at_risk'   => (label: 'At-risk', color: BT.amber),
    'delayed'   => (label: 'Delayed', color: BT.coral),
    'delivered' => (label: 'Delivered', color: BT.mint),
    _           => (label: s, color: BT.mut2),
  };

  int _statusOrder(String s) => switch (s) { 'delayed' => 0, 'at_risk' => 1, _ => 2 };

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(opsBoardProvider);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(opsBoardProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(width: 42, height: 42, alignment: Alignment.center,
                  decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                  child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('LIVE', style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: BT.mut)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('OWNER · COMMAND CENTER',
              style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('The whole floor', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 18),
            board.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load the floor.\n${friendlyError(e)}',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: _content,
            ),
          ],
        ),
      )),
    );
  }

  Widget _content(List<OpsRow> rows) {
    final onTrack = rows.where((r) => r.status == 'on_track').length;
    final atRisk  = rows.where((r) => r.status == 'at_risk').length;
    final delayed = rows.where((r) => r.status == 'delayed').length;

    // needs attention: delayed / at-risk, stuck in a stage, or order-by overdue
    final attention = rows.where((r) =>
      r.status == 'delayed' || r.status == 'at_risk' ||
      (r.daysInStage != null && r.daysInStage! > 7) ||
      (r.nextOrderBy != null && r.nextOrderBy!.isBefore(DateTime.now()))).toList();

    final filtered = (_dept == null ? rows : rows.where((r) => r.currentDiscipline == _dept).toList())
      ..sort((a, b) {
        final s = _statusOrder(a.status).compareTo(_statusOrder(b.status));
        if (s != 0) return s;
        return (b.daysInStage ?? 0).compareTo(a.daysInStage ?? 0);
      });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _hero(rows.length, onTrack, atRisk, delayed, attention.length),
      const SizedBox(height: 8),
      _departmentStrip(rows),
      if (attention.isNotEmpty) ...[
        const SectionLabel('Needs attention'),
        ...attention.take(4).map(_attentionRow),
      ],
      SectionLabel(_dept == null ? 'All active builds · ${filtered.length}'
        : '${_dept_(_dept!).label} · ${filtered.length}'),
      if (filtered.isEmpty)
        const EmptyState(icon: Icons.factory_rounded, tint: BT.lime,
          title: 'Nothing here', subtitle: 'No active builds in this view right now.')
      else
        ...filtered.map(_boardRow),
    ]);
  }

  // ── premium dark hero: the numbers that matter, at a glance ──────────────
  Widget _hero(int total, int onTrack, int atRisk, int delayed, int attention) => Container(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
    decoration: BoxDecoration(
      color: BT.ink,
      borderRadius: BorderRadius.circular(BT.radiusCard),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 16))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('$total', style: display(52, w: FontWeight.w600, c: Colors.white)),
        const SizedBox(width: 10),
        const Padding(padding: EdgeInsets.only(bottom: 10),
          child: Text('active\nbuilds', style: TextStyle(color: Color(0xFFB4AE9E), fontSize: 13, height: 1.15))),
        const Spacer(),
        if (attention > 0) Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: BT.coral, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.priority_high_rounded, size: 14, color: Color(0xFF5A2410)),
            const SizedBox(width: 3),
            Text('$attention need you', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5A2410))),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        _heroStat('$onTrack', 'On-track', BT.lime),
        _heroDiv(),
        _heroStat('$atRisk', 'At-risk', BT.amber),
        _heroDiv(),
        _heroStat('$delayed', 'Delayed', BT.coral),
      ]),
    ]),
  );

  Widget _heroStat(String v, String l, Color c) => Expanded(child: Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(v, style: display(20, w: FontWeight.w600, c: Colors.white)),
      Text(l, style: const TextStyle(color: Color(0xFF918B7C), fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  ]));

  Widget _heroDiv() => Container(width: 1, height: 30, color: const Color(0xFF3A3833));

  // ── department activity: how many builds each department is on now ───────
  Widget _departmentStrip(List<OpsRow> rows) {
    int countFor(String d) => rows.where((r) => r.currentDiscipline == d).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('By department · right now'),
      SizedBox(height: 96, child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final d in _depts) _deptTile(d, countFor(d)),
        ],
      )),
    ]);
  }

  Widget _deptTile(String d, int count) {
    final info = _dept_(d);
    final on = _dept == d;
    final tint = roleColor(d);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _dept = on ? null : d),
      child: Container(
        width: 118,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? BT.ink : BT.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? BT.ink : BT.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(11)),
            child: Icon(info.icon, size: 18, color: d == 'workshop' ? const Color(0xFF4A3410) : BT.ink)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$count', style: display(22, w: FontWeight.w700, c: on ? Colors.white : BT.ink)),
            const SizedBox(width: 5),
            Padding(padding: const EdgeInsets.only(bottom: 4),
              child: Text(info.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: on ? const Color(0xFFB4AE9E) : BT.mut))),
          ]),
        ]),
      ),
    );
  }

  // ── a build row on the board ─────────────────────────────────────────────
  Widget _boardRow(OpsRow r) {
    final sp = _statusPill(r.status);
    final stuck = r.daysInStage != null && r.daysInStage! > 7;
    return Padding(padding: const EdgeInsets.only(bottom: 11), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectDossierScreen(projectId: r.projectId, code: r.code))),
      child: AppCard(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${r.code} · ${r.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          const SizedBox(width: 8),
          StatusPill(sp.label, color: sp.color),
        ]),
        const SizedBox(height: 12),
        // stage + who
        Row(children: [
          _miniBadge(r.currentDiscipline == null ? Icons.pause_circle_outline_rounded : _dept_(r.currentDiscipline!).icon,
            r.currentStageName ?? 'No active stage', roleColor(r.currentDiscipline ?? '')),
          const Spacer(),
          if (r.daysInStage != null)
            Text('${r.daysInStage}d in stage',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: stuck ? BT.coral : BT.mut)),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          const Icon(Icons.person_outline_rounded, size: 15, color: BT.mut),
          const SizedBox(width: 5),
          Expanded(child: Text(
            r.isUnassigned ? 'Unassigned'
              : '${r.assigneeName}${r.subTeamName != null ? ' · ${r.subTeamName}' : ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: r.isUnassigned ? BT.coral : BT.mut,
              fontWeight: r.isUnassigned ? FontWeight.w700 : FontWeight.w600))),
          if (r.pmName != null) Text('PM · ${r.pmName}',
            style: const TextStyle(fontSize: 11.5, color: BT.mut2, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 11),
        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
          value: r.progressPct.clamp(0, 100) / 100, minHeight: 6,
          backgroundColor: BT.track,
          valueColor: AlwaysStoppedAnimation(sp.color))),
        if (r.nextOrderBy != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.local_shipping_outlined, size: 13,
              color: r.nextOrderBy!.isBefore(DateTime.now()) ? BT.coral : BT.mut),
            const SizedBox(width: 5),
            Text('Next order-by · ${_fmt.format(r.nextOrderBy!)}',
              style: TextStyle(fontSize: 11.5,
                color: r.nextOrderBy!.isBefore(DateTime.now()) ? BT.coral : BT.mut,
                fontWeight: FontWeight.w600)),
          ]),
        ],
      ])),
    ));
  }

  Widget _miniBadge(IconData icon, String label, Color tint) => Flexible(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 20, height: 20, alignment: Alignment.center,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 12, color: BT.ink)),
      const SizedBox(width: 7),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.ink))),
    ]),
  ));

  // ── needs-attention row (compact) ────────────────────────────────────────
  Widget _attentionRow(OpsRow r) {
    final overdueOrder = r.nextOrderBy != null && r.nextOrderBy!.isBefore(DateTime.now());
    final stuck = r.daysInStage != null && r.daysInStage! > 7;
    final why = r.status == 'delayed' ? 'Delayed'
      : r.status == 'at_risk' ? 'At-risk'
      : overdueOrder ? 'Order-by passed'
      : stuck ? '${r.daysInStage}d in one stage'
      : 'Needs a look';
    final tint = (r.status == 'delayed' || overdueOrder) ? BT.coral : BT.amber;
    return Padding(padding: const EdgeInsets.only(bottom: 9), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectDossierScreen(projectId: r.projectId, code: r.code))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
        child: Row(children: [
          Container(width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(11)),
            child: Icon(overdueOrder ? Icons.local_shipping_rounded : Icons.warning_amber_rounded,
              size: 18, color: BT.ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.code} · ${r.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text('$why${r.currentStageName != null ? ' · ${r.currentStageName}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
        ]),
      ),
    ));
  }
}

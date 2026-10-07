import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../../shared/role_header.dart';
import '../../shared/animations.dart';
import 'new_design.dart';
import 'design_detail.dart';

/// Designer shell — nav: Studio · Designs · Approvals · Profile.
/// Designers create designs, upload 2D previews + .glb models, submit them for
/// client approval, and act on change requests. Approved models power the 3D
/// showcase everywhere else in the app.
class DesignHome extends ConsumerStatefulWidget {
  const DesignHome({super.key});
  @override
  ConsumerState<DesignHome> createState() => _DesignHomeState();
}

class _DesignHomeState extends ConsumerState<DesignHome> {
  int _tab = 0;
  String _filter = 'all';
  int _buildsPage = 0;
  final PageController _buildsCtrl = PageController(viewportFraction: 0.9);
  static const _labels = ['Studio', 'Designs', 'Approvals'];
  static final _fmt = DateFormat('d MMM');

  @override
  void dispose() {
    _buildsCtrl.dispose();
    super.dispose();
  }

  static ({String label, Color color}) projStatus(String s) => switch (s) {
    'on_track'  => (label: 'On-track', color: BT.lime),
    'at_risk'   => (label: 'At-risk', color: BT.amber),
    'delayed'   => (label: 'Delayed', color: BT.coral),
    'delivered' => (label: 'Delivered', color: BT.mint),
    _           => (label: s, color: BT.mut2),
  };

  static ({String label, Color color}) statusPill(String s) => switch (s) {
    'approved'         => (label: 'Approved', color: BT.lime),
    'pending_approval' => (label: 'Awaiting client', color: BT.amber),
    'revision'         => (label: 'Changes requested', color: BT.coral),
    _                  => (label: 'Draft', color: BT.mut2),
  };

  static String typeLabel(String t) => t.isEmpty ? 'Design' : '${t[0].toUpperCase()}${t.substring(1)}';

  /// A designer can only work on builds a PM actually put them on, so there is
  /// nothing to create against until that happens.
  void _newDesign() {
    final assigned = ref.read(assignedProjectsProvider).valueOrNull;
    if (assigned != null && assigned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: BT.coral,
        content: Text('No builds assigned to you yet — a project manager has to '
                      'assign you a design stage first.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewDesign()))
      .then((_) {
        ref.invalidate(myDesignsProvider);
        ref.invalidate(assignedProjectsProvider);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: TabSwitcher(index: _tab, child: <Widget>[
        _studioTab(), _designsTab(), _approvalsTab(),
      ][_tab])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.home_rounded, Icons.photo_library_rounded, Icons.verified_rounded],
        active: _tab, activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: _newDesign,
      ),
    );
  }

  Widget _header(String kicker, String title) =>
      FadeSlideIn(child: RoleHeader(role: 'design', eyebrow: kicker, title: title));

  // ── STUDIO (home) ─────────────────────────────────────────
  Widget _studioTab() {
    final designs = ref.watch(myDesignsProvider);
    final builds = ref.watch(myAssignedBuildsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(assignedProjectsProvider);
        ref.invalidate(myAssignedBuildsProvider);
        return ref.refresh(myDesignsProvider.future);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 110), children: [
        _header('DESIGN STUDIO', 'My work'),
        const SizedBox(height: 18),

        // The builds a PM has put me on — my whole scope of work, nearest due
        // first, as a swipeable carousel.
        ...builds.when(
          skipLoadingOnRefresh: true,
          loading: () => const <Widget>[SkeletonList(count: 1, leading: true)],
          error: (e, _) => <Widget>[
            ErrorCard('Could not load your builds.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(myAssignedBuildsProvider)),
          ],
          data: (list) => list.isEmpty
            ? const <Widget>[
                EmptyState(icon: Icons.assignment_ind_outlined, tint: BT.pink,
                  title: 'No builds assigned yet',
                  subtitle: 'Once a project manager assigns you a design stage, that '
                            'truck shows up here and you can start uploading.'),
              ]
            : <Widget>[
                FadeSlideIn(delay: Motion.stagger(1), child: _assignedHeader(list)),
                FadeSlideIn(delay: Motion.stagger(2), child: _assignedCarousel(list)),
              ],
        ),
        // The single-build card used to sit flush against the stats grid.
        const SizedBox(height: 16),
        designs.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load designs.\n${friendlyError(e)}'),
          data: (list) {
            final drafts   = list.where((d) => d.status == 'draft').length;
            final awaiting = list.where((d) => d.status == 'pending_approval').length;
            final changes  = list.where((d) => d.status == 'revision').length;
            final approved = list.where((d) => d.status == 'approved').length;
            final attention = list.where((d) => d.status == 'draft' || d.status == 'revision').toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
              Row(children: [
                Expanded(child: _stat('Drafts', drafts, BT.card2, Icons.edit_note_rounded)),
                const SizedBox(width: 11),
                Expanded(child: _stat('Awaiting', awaiting, BT.amber, Icons.hourglass_top_rounded)),
              ]),
              const SizedBox(height: 11),
              Row(children: [
                Expanded(child: _stat('Changes', changes, BT.coral, Icons.rate_review_rounded)),
                const SizedBox(width: 11),
                Expanded(child: _stat('Approved', approved, BT.lime, Icons.verified_rounded)),
              ]),
              const SectionLabel('Needs your attention'),
              if (attention.isEmpty)
                const EmptyState(icon: Icons.check_circle_outline_rounded, tint: BT.lime,
                  title: 'All caught up', subtitle: 'New drafts and change requests will show here.')
              else
                ...attention.map(_designCard),
            ], stepMs: 45));
          },
        ),
      ]),
    );
  }

  Widget _stat(String label, int value, Color tint, IconData icon) => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38, alignment: Alignment.center,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 19, color: BT.ink)),
      const SizedBox(height: 12),
      Text('$value', style: display(28, w: FontWeight.w600)),
      Text(label, style: const TextStyle(color: BT.mut, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]),
  );

  // ── "Assigned to me" carousel ─────────────────────────────
  Widget _assignedHeader(List<AssignedBuild> list) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Text('ASSIGNED TO ME',
        style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: BT.mut)),
      if (list.length > 1) PressableScale(pressedScale: 0.98, haptic: true, onTap: () => _showAllBuilds(list),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('See all ${list.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BT.ink)),
          const Icon(Icons.chevron_right_rounded, size: 16, color: BT.ink),
        ])),
    ]),
  );

  Widget _assignedCarousel(List<AssignedBuild> list) {
    if (list.length == 1) return AssignedBuildCard(b: list.first);
    // The carousel's height is MEASURED from the real cards (every one, the
    // tallest wins), so it fits exactly at every text size. Fixed heights either
    // overflowed at large text or left an empty band under the card. Guessing
    // the tallest card from one field was wrong too: the stage name is one
    // ellipsized line, and what actually adds height is the date chips wrapping.
    return Column(children: [
      _MeasuredHeight(
        probes: [for (final b in list) AssignedBuildCard(b: b)],
        builder: (h) => SizedBox(height: h, child: PageView.builder(
          controller: _buildsCtrl,
          itemCount: list.length,
          onPageChanged: (i) => setState(() => _buildsPage = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedBuilder(
              animation: _buildsCtrl,
              // Neighbouring cards sit a touch smaller and fade, then grow into
              // focus as they slide to the centre.
              builder: (_, child) {
                final page = _buildsCtrl.hasClients && _buildsCtrl.position.haveDimensions
                  ? (_buildsCtrl.page ?? _buildsPage.toDouble()) : _buildsPage.toDouble();
                final d = (page - i).abs().clamp(0.0, 1.0);
                return Opacity(opacity: 1 - 0.35 * d,
                  child: Transform.scale(scale: 1 - 0.05 * d, child: child));
              },
              child: AssignedBuildCard(b: list[i]),
            )),
        )),
      ),
      const SizedBox(height: 12),
      _dots(list.length),
    ]);
  }

  Widget _dots(int count) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    for (int i = 0; i < count; i++) AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: i == _buildsPage ? 20 : 7, height: 7,
      decoration: BoxDecoration(color: i == _buildsPage ? BT.ink : BT.mut2, borderRadius: BorderRadius.circular(999))),
  ]);

  void _showAllBuilds(List<AssignedBuild> list) {
    showModalBottomSheet<void>(
      sheetAnimationStyle: sheetMotion,
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Text('Assigned to me · ${list.length}', style: display(20, w: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Soonest due first.', style: TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 12),
          Flexible(child: ListView(shrinkWrap: true, children: [
            for (final b in list) Padding(padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.code} · ${b.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.flag_rounded, size: 12, color: b.isOverdue ? BT.coral : BT.mut),
                      const SizedBox(width: 4),
                      Text(b.due == null ? 'No due date' : 'Due ${_fmt.format(b.due!)}',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: b.isOverdue ? BT.coral : BT.mut)),
                      const Text('  ·  ', style: TextStyle(color: BT.mut2, fontSize: 11.5)),
                      Text('${b.progressPct}%', style: const TextStyle(fontSize: 11.5, color: BT.mut, fontWeight: FontWeight.w600)),
                    ]),
                  ])),
                  StatusPill(projStatus(b.status).label, color: projStatus(b.status).color),
                ]))),
          ])),
        ]),
      ),
    );
  }

  // ── DESIGNS (full library, filterable) ────────────────────
  Widget _designsTab() {
    final designs = ref.watch(myDesignsProvider);
    const filters = [
      ['all', 'All'], ['draft', 'Drafts'], ['pending_approval', 'Awaiting'],
      ['revision', 'Changes'], ['approved', 'Approved'],
    ];
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myDesignsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 110), children: [
        _header('LIBRARY', 'Designs'),
        const SizedBox(height: 14),
        FadeSlideIn(delay: Motion.stagger(1), child: ChipBar(chips: [
          for (final f in filters) _filterChip(f[0], f[1]),
        ])),
        const SizedBox(height: 14),
        designs.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load.\n${friendlyError(e)}'),
          data: (list) {
            final shown = _filter == 'all' ? list : list.where((d) => d.status == _filter).toList();
            if (shown.isEmpty) {
              return EmptyState(icon: Icons.palette_outlined, tint: BT.pink,
                title: 'No designs here',
                subtitle: list.isEmpty
                  ? 'Designs appear once a PM assigns you a design stage on a build.'
                  : 'Nothing matches this filter. Tap + to start a new design.');
            }
            return Column(children: staggered(shown.map(_designCard).toList()));
          },
        ),
      ]),
    );
  }

  Widget _filterChip(String value, String label) => AppChip(label,
    selected: _filter == value, onTap: () => setState(() => _filter = value));

  // ── APPROVALS (submitted → outcome + feedback) ────────────
  Widget _approvalsTab() {
    final designs = ref.watch(myDesignsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myDesignsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 110), children: [
        _header('CLIENT LOOP', 'Approvals'),
        const SizedBox(height: 16),
        designs.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorCard('Could not load.\n${friendlyError(e)}'),
          data: (list) {
            final submitted = list.where((d) => d.status != 'draft').toList();
            if (submitted.isEmpty) {
              return const EmptyState(icon: Icons.send_outlined, tint: BT.sky,
                title: 'Nothing submitted yet', subtitle: 'Designs you send for approval show their status here.');
            }
            return Column(children: staggered(submitted.map(_designCard).toList()));
          },
        ),
      ]),
    );
  }

  // ── shared design card ────────────────────────────────────
  Widget _designCard(DesignItem d) {
    final st = statusPill(d.status);
    final has3d = d.modelUrl != null && d.modelUrl!.isNotEmpty;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: PressableScale(pressedScale: 0.98, haptic: true, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DesignDetailScreen(artifactId: d.id)))
        .then((_) => ref.invalidate(myDesignsProvider)),
      child: AppCard(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 46, height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.pink.withOpacity(0.5), borderRadius: BorderRadius.circular(13)),
            child: Icon(has3d ? Icons.view_in_ar_rounded : Icons.palette_rounded, size: 22, color: const Color(0xFF4A2438))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${typeLabel(d.type)} design', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text('${d.projectCode ?? '—'}${d.projectName != null ? ' · ${d.projectName}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
          ])),
          StatusPill(st.label, color: st.color),
        ]),
        if (d.status == 'revision' && d.clientFeedback != null && d.clientFeedback!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.rate_review_rounded, size: 15, color: BT.coral),
              const SizedBox(width: 8),
              Expanded(child: Text(d.clientFeedback!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF7A3B2A)))),
            ])),
        ],
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Version ${d.versionNo}${has3d ? ' · 3D model attached' : ''}', style: const TextStyle(color: BT.mut, fontSize: 11.5)),
          const Row(children: [Text('Open', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)), Icon(Icons.chevron_right_rounded, size: 16)]),
        ]),
      ])),
    ));
  }

}

/// One assigned build in the Studio carousel: code, name, status, progress,
/// the stage I hold, my due date and the delivery date.
class AssignedBuildCard extends StatelessWidget {
  final AssignedBuild b;
  const AssignedBuildCard({super.key, required this.b});

  @override
  Widget build(BuildContext context) {
    final st = _DesignHomeState.projStatus(b.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF7E6F0), Color(0xFFFBF8F2)]),
        borderRadius: BorderRadius.circular(BT.radiusCard),
        border: Border.all(color: const Color(0xFFEFD6E6)),
        boxShadow: const [BoxShadow(color: Color(0x11695228), blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.pink, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.local_shipping_rounded, size: 20, color: Color(0xFF4A2438))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.code, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BT.mut, fontSize: 12)),
          ])),
          StatusPill(st.label, color: st.color),
        ]),
        const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${b.progressPct}% complete',
              style: const TextStyle(color: BT.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
            if (b.stageName != null) ...[
              const Spacer(),
              Flexible(child: Text(b.stageName!, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BT.mut2, fontSize: 11.5, fontWeight: FontWeight.w600))),
            ],
          ]),
          const SizedBox(height: 6),
          AnimatedBar(fraction: b.progressPct.clamp(0, 100) / 100, color: st.color, height: 7),
        ]),
        const SizedBox(height: 14),
        // Wrap, not Row: with both dates filled in, the two chips are wider than
        // a carousel card (they overflowed by ~35px even at normal text size).
        Wrap(spacing: 8, runSpacing: 8, children: [
          _dateChip(Icons.flag_rounded, 'Due', b.due, b.isOverdue ? BT.coral : BT.ink),
          _dateChip(Icons.local_shipping_outlined, 'Delivery', b.targetDelivery, BT.mut),
        ]),
      ]),
    );
  }

  Widget _dateChip(IconData icon, String label, DateTime? d, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: BT.line)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text('$label ', style: const TextStyle(fontSize: 10.5, color: BT.mut, fontWeight: FontWeight.w600)),
      Text(d == null ? '—' : _DesignHomeState._fmt.format(d), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    ]),
  );

}

/// Lays every [probes] widget out invisibly (at the page width) and hands the
/// tallest height to [builder], so a fixed-height container like a PageView can
/// fit all of its pages.
class _MeasuredHeight extends StatefulWidget {
  final List<Widget> probes;
  final Widget Function(double height) builder;
  const _MeasuredHeight({required this.probes, required this.builder});
  @override
  State<_MeasuredHeight> createState() => _MeasuredHeightState();
}

class _MeasuredHeightState extends State<_MeasuredHeight> {
  final _key = GlobalKey();
  double? _h;

  void _measure() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_h == null || (h - _h!).abs() > 0.5) setState(() => _h = h);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _measure(); });
    return LayoutBuilder(builder: (context, c) {
      // The PageView shows each page at 90% width (viewportFraction) minus the
      // 12px gap, so measure at that width.
      final w = c.maxWidth * 0.9 - 12;
      // The visible child sizes the outer Stack. The probes are laid out
      // offstage at the page width with unbounded height, stacked on each other,
      // so the inner Stack reports the tallest card's natural height.
      return Stack(clipBehavior: Clip.none, children: [
        if (_h != null) widget.builder(_h!)
        else Opacity(opacity: 0, child: SizedBox(width: w, child: widget.probes.first)),
        Positioned(left: 0, top: 0, width: w, child: Offstage(
          child: UnconstrainedBox(alignment: Alignment.topLeft, constrainedAxis: Axis.horizontal,
            child: Stack(key: _key, children: [
              for (final p in widget.probes) SizedBox(width: w, child: p),
            ])))),
      ]);
    });
  }
}

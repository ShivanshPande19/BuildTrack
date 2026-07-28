import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../common/notifications.dart';
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
  static const _labels = ['Studio', 'Designs', 'Approvals', 'Profile'];

  static ({String label, Color color}) statusPill(String s) => switch (s) {
    'approved'         => (label: 'Approved', color: BT.lime),
    'pending_approval' => (label: 'Awaiting client', color: BT.amber),
    'revision'         => (label: 'Changes requested', color: BT.coral),
    _                  => (label: 'Draft', color: BT.mut2),
  };

  static String typeLabel(String t) => t.isEmpty ? 'Design' : '${t[0].toUpperCase()}${t.substring(1)}';

  void _newDesign() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewDesign()))
      .then((_) => ref.invalidate(myDesignsProvider));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: [
        _studioTab(), _designsTab(), _approvalsTab(), _profileTab(),
      ])),
      bottomNavigationBar: PillNav(
        icons: const [Icons.home_rounded, Icons.photo_library_rounded, Icons.verified_rounded, Icons.person_rounded],
        active: _tab, activeLabel: _labels[_tab],
        onTap: (i) => setState(() => _tab = i),
        onAction: _newDesign,
      ),
    );
  }

  Widget _bell() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
    child: Container(width: 42, height: 42, alignment: Alignment.center,
      decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
      child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink)),
  );

  Widget _header(String kicker, String title) => Row(
    crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(kicker, style: const TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(title, style: display(29, w: FontWeight.w500)),
      ]),
      Padding(padding: const EdgeInsets.only(top: 4), child: _bell()),
    ]);

  // ── STUDIO (home) ─────────────────────────────────────────
  Widget _studioTab() {
    final designs = ref.watch(myDesignsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myDesignsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        _header('DESIGN STUDIO', 'My work'),
        const SizedBox(height: 18),
        designs.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load designs.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final drafts   = list.where((d) => d.status == 'draft').length;
            final awaiting = list.where((d) => d.status == 'pending_approval').length;
            final changes  = list.where((d) => d.status == 'revision').length;
            final approved = list.where((d) => d.status == 'approved').length;
            final attention = list.where((d) => d.status == 'draft' || d.status == 'revision').toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            ]);
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

  // ── DESIGNS (full library, filterable) ────────────────────
  Widget _designsTab() {
    final designs = ref.watch(myDesignsProvider);
    const filters = [
      ['all', 'All'], ['draft', 'Drafts'], ['pending_approval', 'Awaiting'],
      ['revision', 'Changes'], ['approved', 'Approved'],
    ];
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myDesignsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        _header('LIBRARY', 'Designs'),
        const SizedBox(height: 14),
        SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final f in filters) Padding(padding: const EdgeInsets.only(right: 8), child: _filterChip(f[0], f[1])),
        ])),
        const SizedBox(height: 8),
        designs.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 50), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final shown = _filter == 'all' ? list : list.where((d) => d.status == _filter).toList();
            if (shown.isEmpty) {
              return const EmptyState(icon: Icons.palette_outlined, tint: BT.pink,
                title: 'No designs here', subtitle: 'Tap + to start a new design for a truck.');
            }
            return Column(children: shown.map(_designCard).toList());
          },
        ),
      ]),
    );
  }

  Widget _filterChip(String value, String label) {
    final on = _filter == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? BT.ink : BT.card, borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? Colors.transparent : BT.line)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : BT.ink)),
      ),
    );
  }

  // ── APPROVALS (submitted → outcome + feedback) ────────────
  Widget _approvalsTab() {
    final designs = ref.watch(myDesignsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(myDesignsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        _header('CLIENT LOOP', 'Approvals'),
        const SizedBox(height: 16),
        designs.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 50), child: Center(child: CircularProgressIndicator(color: BT.ink))),
          error: (e, _) => AppCard(child: Text('Could not load.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
          data: (list) {
            final submitted = list.where((d) => d.status != 'draft').toList();
            if (submitted.isEmpty) {
              return const EmptyState(icon: Icons.send_outlined, tint: BT.sky,
                title: 'Nothing submitted yet', subtitle: 'Designs you send for approval show their status here.');
            }
            return Column(children: submitted.map(_designCard).toList());
          },
        ),
      ]),
    );
  }

  // ── shared design card ────────────────────────────────────
  Widget _designCard(DesignItem d) {
    final st = statusPill(d.status);
    final has3d = d.modelUrl != null && d.modelUrl!.isNotEmpty;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DesignDetailScreen(artifactId: d.id)))
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

  // ── PROFILE (inline) ──────────────────────────────────────
  Widget _profileTab() {
    final u = sb.auth.currentUser;
    final name = (u?.userMetadata?['full_name'] as String?) ?? u?.email?.split('@').first ?? 'Designer';
    final email = u?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
      Text('Profile', style: display(29, w: FontWeight.w500)),
      const SizedBox(height: 18),
      AppCard(padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20), child: Column(children: [
        Container(width: 74, height: 74, alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3C3DD), Color(0xFFC4A5EC)])),
          child: Text(initial, style: display(26, w: FontWeight.w600, c: const Color(0xFF4A2438)))),
        const SizedBox(height: 14),
        Text(name, style: display(20, w: FontWeight.w600)),
        const SizedBox(height: 8),
        const StatusPill('Design', color: BT.pink),
        if (email.isNotEmpty) ...[const SizedBox(height: 10), Text(email, style: const TextStyle(color: BT.mut, fontSize: 12.5))],
      ])),
      const SectionLabel('Account'),
      _setRow(Icons.notifications_none_rounded, 'Notifications', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
      _setRow(Icons.person_outline_rounded, 'My details', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Account details — coming soon')))),
      const SizedBox(height: 20),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => sb.auth.signOut().then((_) { if (mounted) context.go('/login'); }),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.logout_rounded, size: 19, color: BT.coral)),
          const SizedBox(width: 15),
          const Text('Log out', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.coral)),
        ]),
      ),
    ]);
  }

  Widget _setRow(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 19, color: BT.ink)),
        const SizedBox(width: 15),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ])),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../client/truck_3d.dart';
import 'new_design.dart';

/// Designer — one design: 3D/2D preview, status, client feedback, version
/// history, and the actions to submit for approval or upload a new version.
class DesignDetailScreen extends ConsumerStatefulWidget {
  final String artifactId;
  const DesignDetailScreen({super.key, required this.artifactId});
  @override
  ConsumerState<DesignDetailScreen> createState() => _DesignDetailScreenState();
}

class _DesignDetailScreenState extends ConsumerState<DesignDetailScreen> {
  bool _busy = false;
  static final _fmt = DateFormat('d MMM yyyy');

  ({String label, Color color}) _statusPill(String s) => switch (s) {
    'approved'         => (label: 'Approved', color: BT.lime),
    'pending_approval' => (label: 'Awaiting client', color: BT.amber),
    'revision'         => (label: 'Changes requested', color: BT.coral),
    _                  => (label: 'Draft', color: BT.mut2),
  };

  String _typeLabel(String t) => t.isEmpty ? 'Design' : '${t[0].toUpperCase()}${t.substring(1)}';

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(designRepoProvider).submitForApproval(widget.artifactId);
      ref.invalidate(designDetailProvider(widget.artifactId));
      ref.invalidate(myDesignsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: BT.ink, content: Text('Sent to client for approval 🎉')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: BT.coral, content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _newVersion(DesignItem d) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewDesign(
      artifactId: widget.artifactId,
      lockedProjectLabel: d.projectCode ?? d.projectName,
      lockedType: d.type,
    ))).then((_) => ref.invalidate(designDetailProvider(widget.artifactId)));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(designDetailProvider(widget.artifactId));
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(designDetailProvider(widget.artifactId).future),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 30), children: [
          Row(children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
          ]),
          const SizedBox(height: 12),
          detail.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => AppCard(child: Text('Could not load design.\n$e', style: const TextStyle(color: BT.coral, fontSize: 13))),
            data: (d) => _content(d),
          ),
        ]),
      )),
    );
  }

  Widget _content(DesignDetailData data) {
    final d = data.design;
    final st = _statusPill(d.status);
    final has3d = d.modelUrl != null && d.modelUrl!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_typeLabel(d.type)} design', style: display(26, w: FontWeight.w600)),
          const SizedBox(height: 3),
          Text('${d.projectCode ?? '—'}${d.projectName != null ? ' · ${d.projectName}' : ''}',
            style: const TextStyle(color: BT.mut, fontSize: 13)),
        ])),
        const SizedBox(width: 10),
        StatusPill(st.label, color: st.color),
      ]),
      const SizedBox(height: 16),

      // preview: 3D if a model exists, else the 2D image, else a placeholder
      if (has3d)
        Truck3DPreview(glbUrl: d.modelUrl!, label: '${d.projectName ?? d.type} design', height: 230)
      else if (d.imageUrl != null && d.imageUrl!.isNotEmpty)
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(d.imageUrl!, height: 210, width: double.infinity, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _previewPlaceholder(), loadingBuilder: (c, w, p) => p == null ? w : _previewPlaceholder()))
      else
        _previewPlaceholder(),

      // client feedback when changes are requested
      if (d.status == 'revision' && d.clientFeedback != null && d.clientFeedback!.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: const [
              Icon(Icons.rate_review_rounded, size: 17, color: BT.coral), SizedBox(width: 8),
              Text('Client requested changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF7A3B2A))),
            ]),
            const SizedBox(height: 8),
            Text(d.clientFeedback!, style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF7A3B2A))),
          ])),
      ],

      // status banner for pending / approved
      if (d.status == 'pending_approval') ...[
        const SizedBox(height: 14),
        _banner(BT.amber, Icons.hourglass_top_rounded, 'Waiting for the client', 'They\'ve been notified to review this design.'),
      ] else if (d.status == 'approved') ...[
        const SizedBox(height: 14),
        _banner(BT.lime, Icons.verified_rounded, 'Approved by the client', 'This model now shows across the app for this truck.'),
      ],

      if (d.changeNote != null && d.changeNote!.isNotEmpty) ...[
        const SectionLabel('Latest note'),
        AppCard(padding: const EdgeInsets.all(16), child: Text(d.changeNote!, style: const TextStyle(fontSize: 13.5, height: 1.4))),
      ],

      const SectionLabel('Version history'),
      ...data.versions.map((v) => Padding(padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
            child: Text('v${v.versionNo}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.changeNote == null || v.changeNote!.isEmpty ? 'Version ${v.versionNo}' : v.changeNote!,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(v.createdAt == null ? '' : _fmt.format(v.createdAt!), style: const TextStyle(color: BT.mut, fontSize: 11.5)),
          ])),
          if (v.modelUrl != null && v.modelUrl!.isNotEmpty)
            const Icon(Icons.view_in_ar_rounded, size: 18, color: BT.mut2),
        ]))),
      ),

      const SizedBox(height: 18),
      if (_busy) const Center(child: CircularProgressIndicator(color: BT.ink))
      else ..._actions(d),
    ]);
  }

  List<Widget> _actions(DesignItem d) {
    // draft → submit + new version; revision → new version (primary); others → new version
    if (d.status == 'draft') {
      return [
        Row(children: [
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _newVersion(d),
            child: Container(height: 54, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
              child: const Text('New version', style: TextStyle(fontWeight: FontWeight.w600))),
          )),
          const SizedBox(width: 11),
          Expanded(child: PrimaryButton('Submit for approval', icon: Icons.send_rounded, onTap: _submit)),
        ]),
      ];
    }
    return [
      PrimaryButton(d.status == 'revision' ? 'Upload revised version' : 'Upload new version',
        icon: Icons.add_photo_alternate_rounded, onTap: () => _newVersion(d)),
    ];
  }

  Widget _banner(Color tint, IconData icon, String title, String sub) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: tint.withOpacity(0.35), borderRadius: BorderRadius.circular(18), border: Border.all(color: tint)),
    child: Row(children: [
      Container(width: 40, height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: BT.ink)),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: BT.mut, fontSize: 12, height: 1.3)),
      ])),
    ]),
  );

  Widget _previewPlaceholder() => Container(
    height: 200,
    decoration: BoxDecoration(color: const Color(0xFFF5F3EA), borderRadius: BorderRadius.circular(20), border: Border.all(color: BT.line)),
    child: const Center(child: Icon(Icons.image_outlined, size: 44, color: BT.mut2)),
  );
}

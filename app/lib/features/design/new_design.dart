import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../client/truck_3d.dart';

/// Designer — create a new design (pick project + type) OR add a new version to
/// an existing design (project/type locked). Attach a .glb model + optional 2D
/// preview + a change note, then save as draft or submit for client approval.
class NewDesign extends ConsumerStatefulWidget {
  /// When set, this screen adds a new version to an existing artifact.
  final String? artifactId;
  final String? lockedProjectLabel; // shown read-only when adding a version
  final String? lockedType;
  const NewDesign({super.key, this.artifactId, this.lockedProjectLabel, this.lockedType});

  @override
  ConsumerState<NewDesign> createState() => _NewDesignState();
}

class _NewDesignState extends ConsumerState<NewDesign> {
  final _model = TextEditingController();
  final _image = TextEditingController();
  final _note = TextEditingController();
  String? _projectId;
  late String _type;
  String? _previewUrl;
  bool _saving = false;
  String? _error;

  bool get _isVersion => widget.artifactId != null;

  static const _types = [
    ['layout', 'Layout'], ['interior', 'Interior'], ['exterior', 'Exterior'], ['branding', 'Branding'],
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.lockedType ?? 'layout';
  }

  @override
  void dispose() {
    _model.dispose();
    _image.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(bool submit) async {
    final model = _model.text.trim();
    final image = _image.text.trim();
    if (!_isVersion && _projectId == null) {
      setState(() => _error = 'Please choose a project.');
      return;
    }
    if (model.isEmpty && image.isEmpty) {
      setState(() => _error = 'Add a 3D model (.glb) URL or a preview image URL.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(designRepoProvider);
      if (_isVersion) {
        await repo.addVersion(
          artifactId: widget.artifactId!, modelUrl: model, imageUrl: image,
          changeNote: _note.text.trim(), submit: submit);
      } else {
        await repo.create(
          projectId: _projectId!, type: _type, modelUrl: model, imageUrl: image,
          changeNote: _note.text.trim(), submit: submit);
      }
      ref.invalidate(myDesignsProvider);
      if (widget.artifactId != null) ref.invalidate(designDetailProvider(widget.artifactId!));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink,
          content: Text(submit ? 'Sent to client for approval 🎉' : 'Saved as draft')));
      }
    } catch (e) {
      setState(() { _saving = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(allProjectsProvider).valueOrNull ?? const <Project>[];
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
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
          Text(_isVersion ? 'New version' : 'New design', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(_isVersion
              ? 'Upload an updated model/preview and send it back for approval.'
              : 'Attach a 3D model + preview and send it to the client.',
            style: const TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 18),

          if (_isVersion) ...[
            _label('DESIGN'),
            Container(height: 52, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: Text('${widget.lockedProjectLabel ?? 'Project'} · ${_typeLabel(_type)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BT.ink))),
            const SizedBox(height: 11),
          ] else ...[
            _label('PROJECT'),
            _dropdown<String>(value: _projectId, hint: 'Select a truck',
              items: [for (final p in projects) DropdownMenuItem(value: p.id, child: Text('${p.code} · ${p.name}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _projectId = v)),
            const SizedBox(height: 14),
            _label('DESIGN TYPE'),
            Wrap(spacing: 9, runSpacing: 9, children: _types.map(_typeChip).toList()),
            const SizedBox(height: 14),
          ],

          _label('3D MODEL URL (.glb)'),
          _textField(_model, 'https://…/truck.glb', keyboard: TextInputType.url),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() { _model.text = kDemoTruckGlb; _previewUrl = kDemoTruckGlb; }),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome_rounded, size: 15, color: BT.ink), SizedBox(width: 6),
                Text('Use demo truck model', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ])),
          ),
          const SizedBox(height: 12),

          // live preview of the entered model
          if (_model.text.trim().isNotEmpty) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _previewUrl = _model.text.trim()),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.visibility_rounded, size: 15, color: BT.lime), SizedBox(width: 6),
                  Text('Preview 3D model', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ])),
            ),
            const SizedBox(height: 12),
          ],
          if (_previewUrl != null && _previewUrl!.isNotEmpty) ...[
            Truck3DPreview(glbUrl: _previewUrl!, label: 'Design preview', height: 210),
            const SizedBox(height: 14),
          ],

          _label('PREVIEW IMAGE URL (optional)'),
          _textField(_image, 'https://…/render.png', keyboard: TextInputType.url),
          const SizedBox(height: 14),

          _label('CHANGE NOTE (optional)'),
          _textField(_note, 'What changed / a note for the client', lines: 3),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

          const SizedBox(height: 22),
          if (_saving) const Center(child: CircularProgressIndicator(color: BT.ink))
          else Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _save(false),
              child: Container(height: 54, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
                child: const Text('Save as draft', style: TextStyle(fontWeight: FontWeight.w600))),
            )),
            const SizedBox(width: 11),
            Expanded(child: PrimaryButton('Submit for approval', icon: Icons.send_rounded, onTap: () => _save(true))),
          ]),
        ],
      )),
    );
  }

  static String _typeLabel(String t) => t.isEmpty ? 'Design' : '${t[0].toUpperCase()}${t.substring(1)}';

  Widget _typeChip(List<String> t) {
    final on = _type == t[0];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() { _type = t[0]; _error = null; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: on ? BT.lime : BT.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Colors.transparent : BT.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: on ? BT.ink : BT.mut2, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(t[1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BT.ink)),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(t, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)));

  Widget _textField(TextEditingController c, String hint, {TextInputType? keyboard, int lines = 1}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: lines > 1 ? 8 : 0),
    constraints: BoxConstraints(minHeight: lines > 1 ? 0 : 52),
    alignment: lines > 1 ? null : Alignment.center,
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: TextField(controller: c, keyboardType: keyboard, minLines: lines, maxLines: lines,
      onChanged: (_) { if (lines == 1) setState(() {}); },
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
      decoration: InputDecoration(isDense: true, border: InputBorder.none,
        hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500))),
  );

  Widget _dropdown<T>({required T? value, required String hint,
      required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => Container(
    height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value, isExpanded: true, hint: Text(hint, style: const TextStyle(color: BT.mut2, fontSize: 14)),
      icon: const Icon(Icons.expand_more_rounded, color: BT.mut2),
      style: const TextStyle(color: BT.ink, fontSize: 14, fontWeight: FontWeight.w600),
      items: items, onChanged: onChanged,
    )),
  );
}

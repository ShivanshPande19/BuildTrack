import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../client/truck_3d.dart';

/// Designer — create a new design (pick project + type) OR add a new version to
/// an existing design (project/type locked). The designer uploads a .glb model
/// (+ optional 2D preview) straight from their device — it goes to Supabase
/// Storage automatically — then saves as draft or submits for client approval.
class NewDesign extends ConsumerStatefulWidget {
  final String? artifactId;
  final String? lockedProjectLabel;
  final String? lockedType;
  const NewDesign({super.key, this.artifactId, this.lockedProjectLabel, this.lockedType});

  @override
  ConsumerState<NewDesign> createState() => _NewDesignState();
}

class _NewDesignState extends ConsumerState<NewDesign> {
  final _note = TextEditingController();
  String? _projectId;
  late String _type;

  String? _modelUrl, _modelName;
  String? _imageUrl, _imageName;
  bool _uploadingModel = false, _uploadingImage = false;
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
    _note.dispose();
    super.dispose();
  }

  // ── file pick + upload ────────────────────────────────────
  Future<void> _pickModel() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final name = f.name;
    if (!name.toLowerCase().endsWith('.glb')) {
      setState(() => _error = 'Please pick a .glb file (Blender → Export → glTF Binary).');
      return;
    }
    final bytes = f.bytes;
    if (bytes == null) { setState(() => _error = 'Could not read the file. Try again.'); return; }
    if (bytes.length > 25 * 1024 * 1024) {
      setState(() => _error = 'That .glb is over 25 MB — ask design to export a lighter model (2–10 MB).');
      return;
    }
    setState(() { _uploadingModel = true; _error = null; });
    try {
      final url = await ref.read(designRepoProvider).uploadFile(bytes, filename: name, contentType: 'model/gltf-binary');
      setState(() { _modelUrl = url; _modelName = name; _uploadingModel = false; });
    } catch (e) {
      setState(() { _uploadingModel = false; _error = 'Upload failed: $e'; });
    }
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final name = f.name.toLowerCase();
    final ok = ['.png', '.jpg', '.jpeg', '.webp'].any(name.endsWith);
    if (!ok) { setState(() => _error = 'Please pick an image (png / jpg / webp).'); return; }
    final bytes = f.bytes;
    if (bytes == null) { setState(() => _error = 'Could not read the image.'); return; }
    final ct = name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    setState(() { _uploadingImage = true; _error = null; });
    try {
      final url = await ref.read(designRepoProvider).uploadFile(bytes, filename: f.name, contentType: ct);
      setState(() { _imageUrl = url; _imageName = f.name; _uploadingImage = false; });
    } catch (e) {
      setState(() { _uploadingImage = false; _error = 'Upload failed: $e'; });
    }
  }

  Future<void> _save(bool submit) async {
    if (!_isVersion && _projectId == null) { setState(() => _error = 'Please choose a project.'); return; }
    if ((_modelUrl == null || _modelUrl!.isEmpty) && (_imageUrl == null || _imageUrl!.isEmpty)) {
      setState(() => _error = 'Upload a 3D model (.glb) or a preview image first.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(designRepoProvider);
      if (_isVersion) {
        await repo.addVersion(artifactId: widget.artifactId!, modelUrl: _modelUrl, imageUrl: _imageUrl,
          changeNote: _note.text.trim(), submit: submit);
      } else {
        await repo.create(projectId: _projectId!, type: _type, modelUrl: _modelUrl, imageUrl: _imageUrl,
          changeNote: _note.text.trim(), submit: submit);
      }
      ref.invalidate(myDesignsProvider);
      if (widget.artifactId != null) ref.invalidate(designDetailProvider(widget.artifactId!));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink, content: Text(submit ? 'Sent to client for approval 🎉' : 'Saved as draft')));
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
              : 'Upload a 3D model + preview and send it to the client.',
            style: const TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 18),

          if (_isVersion) ...[
            _label('DESIGN'),
            Container(height: 52, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: Text('${widget.lockedProjectLabel ?? 'Project'} · ${_typeLabel(_type)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BT.ink))),
            const SizedBox(height: 14),
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

          // ── 3D MODEL ──
          _label('3D MODEL (.glb)'),
          if (_uploadingModel)
            _uploadingBox('Uploading model…')
          else if (_modelUrl != null) ...[
            _fileChip(Icons.view_in_ar_rounded, _modelName ?? 'model.glb', onReplace: _pickModel),
            const SizedBox(height: 10),
            Truck3DPreview(glbUrl: _modelUrl!, label: 'Design preview', height: 210),
          ] else Row(children: [
            Expanded(child: _uploadButton(Icons.upload_file_rounded, 'Upload .glb', _pickModel)),
            const SizedBox(width: 10),
            _demoButton(),
          ]),
          const SizedBox(height: 16),

          // ── PREVIEW IMAGE (optional) ──
          _label('PREVIEW IMAGE (optional)'),
          if (_uploadingImage)
            _uploadingBox('Uploading image…')
          else if (_imageUrl != null) ...[
            _fileChip(Icons.image_rounded, _imageName ?? 'image', onReplace: _pickImage),
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(_imageUrl!,
              height: 150, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          ] else _uploadButton(Icons.add_photo_alternate_rounded, 'Upload image', _pickImage),
          const SizedBox(height: 16),

          _label('CHANGE NOTE (optional)'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
            child: TextField(controller: _note, minLines: 3, maxLines: 4,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none,
                hintText: 'What changed / a note for the client',
                hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w500))),
          ),

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

  // ── small building blocks ─────────────────────────────────
  Widget _uploadButton(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque, onTap: onTap,
    child: Container(height: 54, alignment: Alignment.center,
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 19, color: BT.ink), const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ])),
  );

  Widget _demoButton() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() { _modelUrl = kDemoTruckGlb; _modelName = 'Demo truck.glb'; _error = null; }),
    child: Container(height: 54, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
      decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(16)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_rounded, size: 17, color: BT.ink), SizedBox(width: 7),
        Text('Demo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ])),
  );

  Widget _fileChip(IconData icon, String name, {required VoidCallback onReplace}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
    child: Row(children: [
      Container(width: 34, height: 34, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.lime, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: BT.ink)),
      const SizedBox(width: 11),
      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
      const SizedBox(width: 8),
      GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onReplace,
        child: const Text('Replace', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: BT.mut)),
      ),
    ]),
  );

  Widget _uploadingBox(String label) => Container(
    height: 54, alignment: Alignment.center,
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: BT.ink)),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: BT.mut)),
    ]),
  );

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

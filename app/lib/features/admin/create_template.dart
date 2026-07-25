import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — build a custom workflow template (name + ordered stages with durations).
/// On save, returns the new template (OptRef) so the onboarding dropdown can select it.
class CreateTemplate extends ConsumerStatefulWidget {
  const CreateTemplate({super.key});
  @override
  ConsumerState<CreateTemplate> createState() => _CreateTemplateState();
}

class _CreateTemplateState extends ConsumerState<CreateTemplate> {
  final _name = TextEditingController();
  final List<TextEditingController> _stageName = [];
  final List<TextEditingController> _stageDays = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // sensible starting point — user can edit / remove / add
    for (final s in const [
      ['Design & Layout', 4], ['Chassis & Structure', 7], ['Exterior cladding', 3],
      ['Electrical work', 4], ['Interior & Equipment', 3], ['Paint & Branding', 2], ['Testing & Delivery', 2],
    ]) {
      _stageName.add(TextEditingController(text: s[0] as String));
      _stageDays.add(TextEditingController(text: '${s[1]}'));
    }
  }

  void _addStage() => setState(() {
    _stageName.add(TextEditingController());
    _stageDays.add(TextEditingController(text: '2'));
  });

  void _removeStage(int i) => setState(() {
    _stageName.removeAt(i); _stageDays.removeAt(i);
  });

  Future<void> _save() async {
    final stages = <StageDraft>[];
    for (var i = 0; i < _stageName.length; i++) {
      final n = _stageName[i].text.trim();
      if (n.isEmpty) continue;
      stages.add(StageDraft(n, int.tryParse(_stageDays[i].text.trim()) ?? 1));
    }
    if (_name.text.trim().isEmpty || stages.isEmpty) {
      setState(() => _error = 'Template name and at least one stage are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final created = await ref.read(adminRepoProvider).createTemplate(_name.text.trim(), null, stages);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() { _error = 'Failed: $e'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 18)),
          ]),
          Text('New template', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Define the build stages and their durations.', style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 18),
          _text('Template name', _name, hint: 'Compact Kiosk'),
          const SectionLabel('Stages (in order)'),
          ...List.generate(_stageName.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(width: 26, height: 26, alignment: Alignment.center,
                decoration: const BoxDecoration(color: BT.card2, shape: BoxShape.circle),
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BT.mut))),
              const SizedBox(width: 10),
              Expanded(child: _boxField(_stageName[i], 'Stage name')),
              const SizedBox(width: 8),
              SizedBox(width: 64, child: _boxField(_stageDays[i], 'days', number: true)),
              IconButton(onPressed: () => _removeStage(i), icon: const Icon(Icons.close, size: 18, color: BT.mut2)),
            ]),
          )),
          GestureDetector(onTap: _addStage, child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BT.line), color: BT.card),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 18, color: BT.ink), SizedBox(width: 6),
              Text('Add stage', style: TextStyle(fontWeight: FontWeight.w600)),
            ]))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Save template', icon: Icons.check, onTap: _save),
        ],
      )),
    );
  }

  Widget _text(String label, TextEditingController c, {String? hint}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextField(controller: c, decoration: InputDecoration(labelText: label, hintText: hint,
      border: InputBorder.none, labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
  );

  Widget _boxField(TextEditingController c, String hint, {bool number = false}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: TextField(controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(hintText: hint, border: InputBorder.none, isDense: true,
        hintStyle: const TextStyle(color: BT.mut2, fontSize: 13))),
  );
}

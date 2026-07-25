import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — Onboard a new project. Creates the project, then generates its
/// stages + backward-scheduled dates via fn_onboard_project.
class OnboardProject extends ConsumerStatefulWidget {
  const OnboardProject({super.key});
  @override
  ConsumerState<OnboardProject> createState() => _OnboardProjectState();
}

class _OnboardProjectState extends ConsumerState<OnboardProject> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  Ref? _template, _client, _pm;
  DateTime? _target;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_code.text.isEmpty || _name.text.isEmpty || _template == null || _target == null) {
      setState(() => _error = 'Code, name, template and delivery date are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(adminRepoProvider).onboard(
        code: _code.text.trim(), name: _name.text.trim(),
        templateId: _template!.id, clientId: _client?.id, pmId: _pm?.id, target: _target!);
      ref.invalidate(fleetProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Project ${_code.text} onboarded'), backgroundColor: BT.ink));
      }
    } catch (e) {
      setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider);
    final clients = ref.watch(clientsProvider);
    final pms = ref.watch(pmsProvider);
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 18)),
            const Spacer(),
          ]),
          Text('New project', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Creates the build + auto-schedules its stages.', style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 20),
          _text('Project code', _code, hint: 'AZ-142'),
          _text('Truck name', _name, hint: 'Juice Express'),
          _dropdown('Workflow template', templates, _template, (v) => setState(() => _template = v)),
          _dropdown('Client (optional)', clients, _client, (v) => setState(() => _client = v)),
          _dropdown('Project manager (optional)', pms, _pm, (v) => setState(() => _pm = v)),
          _dateField(),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Onboard project', icon: Icons.check, onTap: _submit),
        ],
      )),
    );
  }

  Widget _text(String label, TextEditingController c, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(controller: c, decoration: InputDecoration(labelText: label, hintText: hint,
        border: InputBorder.none, labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
    ),
  );

  Widget _dropdown(String label, AsyncValue<List<Ref>> options, Ref? value, ValueChanged<Ref?> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: options.when(
        loading: () => const Padding(padding: EdgeInsets.all(14), child: Text('Loading…', style: TextStyle(color: BT.mut))),
        error: (e, _) => Padding(padding: const EdgeInsets.all(14), child: Text('Error loading $label', style: const TextStyle(color: BT.coral))),
        data: (list) => DropdownButtonHideUnderline(child: DropdownButton<Ref>(
          isExpanded: true, value: value, hint: Text(label, style: const TextStyle(color: BT.mut, fontSize: 14)),
          items: list.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
          onChanged: onChanged)),
      ),
    ),
  );

  Widget _dateField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GestureDetector(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
        if (d != null) setState(() => _target = d);
      },
      child: Container(
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_target == null ? 'Target delivery date' : _target!.toIso8601String().split('T').first,
            style: TextStyle(color: _target == null ? BT.mut : BT.ink, fontSize: 14, fontWeight: _target == null ? FontWeight.normal : FontWeight.w600)),
          const Icon(Icons.calendar_today_rounded, size: 18, color: BT.mut),
        ]),
      ),
    ),
  );
}

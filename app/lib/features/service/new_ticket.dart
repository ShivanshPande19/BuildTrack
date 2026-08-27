import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Service — log a request that came in outside the app (a phone call, a visit).
/// Only delivered trucks can be picked: after-sales starts at handover.
class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});
  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _desc = TextEditingController();
  String? _projectId;
  String _category = 'equipment';
  String _priority = 'medium';
  bool _saving = false;
  String? _error;

  static const _cats = [
    ['equipment', 'Equipment'], ['electrical', 'Electrical'],
    ['cosmetic', 'Cosmetic'], ['other', 'Other'],
  ];
  static const _prios = [
    ['high', 'High · 4h'], ['medium', 'Medium · 24h'], ['low', 'Low · 72h'],
  ];

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_projectId == null) {
      setState(() => _error = 'Pick which truck this is about.');
      return;
    }
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'Describe the issue.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(serviceRepoProvider).createTicket(
        projectId: _projectId!, category: _category,
        description: _desc.text.trim(), priority: _priority);
      ref.invalidate(serviceTicketsProvider);
      ref.invalidate(deliveredTrucksProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Ticket logged')));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trucks = ref.watch(deliveredTrucksProvider).valueOrNull ?? const <DeliveredTruck>[];
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle,
                  border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
          ]),
          const SizedBox(height: 12),
          Text('New ticket', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('For a request that came in by phone or on site.',
            style: TextStyle(color: BT.mut, fontSize: 13)),

          const SectionLabel('Truck'),
          if (trucks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFFBE4E0),
                borderRadius: BorderRadius.circular(14)),
              child: const Text(
                'No delivered trucks yet. A build only enters after-sales once its '
                'project manager marks it delivered.',
                style: TextStyle(fontSize: 12.5, height: 1.35)),
            )
          else
            AppSelectField<String>(
              hint: 'Select a truck', title: 'Choose a truck', value: _projectId,
              options: [for (final d in trucks) SelectOption(d.project.id, '${d.project.code} · ${d.project.name}')],
              onChanged: (v) => setState(() => _projectId = v),
            ),

          const SectionLabel('Category'),
          Wrap(spacing: 9, runSpacing: 9, children: _cats.map((c) =>
            _chip(c[1], _category == c[0], () => setState(() => _category = c[0]))).toList()),

          const SectionLabel('Priority'),
          Wrap(spacing: 9, runSpacing: 9, children: _prios.map((p) =>
            _chip(p[1], _priority == p[0], () => setState(() => _priority = p[0]))).toList()),
          const SizedBox(height: 6),
          const Padding(padding: EdgeInsets.only(left: 4),
            child: Text('Priority sets the SLA deadline the queue is sorted by.',
              style: TextStyle(color: BT.mut2, fontSize: 11.5))),

          const SectionLabel('Issue'),
          Container(
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BT.line)),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(controller: _desc, maxLines: 4,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: BT.ink),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none,
                hintText: 'Client phoned: fridge is not cooling…',
                hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w400))),
          ),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!,
              style: const TextStyle(color: BT.coral, fontSize: 12.5, height: 1.35))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Log ticket', icon: Icons.add_rounded, onTap: _submit),
        ],
      )),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(color: on ? BT.ink : BT.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? BT.ink : BT.line)),
      child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
        color: on ? Colors.white : BT.mut)),
    ),
  );
}

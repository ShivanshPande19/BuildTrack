import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Client — raise a support request (creates a ticket).
class RaiseRequest extends ConsumerStatefulWidget {
  final String projectId;
  const RaiseRequest({super.key, required this.projectId});
  @override
  ConsumerState<RaiseRequest> createState() => _RaiseRequestState();
}

class _RaiseRequestState extends ConsumerState<RaiseRequest> {
  final _desc = TextEditingController();
  String _category = 'equipment';
  bool _saving = false;
  String? _error;

  static const _cats = [
    ['equipment', 'Equipment issue'], ['electrical', 'Electrical'],
    ['cosmetic', 'Cosmetic'], ['other', 'Other'],
  ];

  Future<void> _submit() async {
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'Please describe the issue.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(clientRepoProvider).raiseTicket(
        projectId: widget.projectId, category: _category, description: _desc.text.trim());
      ref.invalidate(myTicketsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Request submitted — we\'ll get back to you.')));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Raise a request', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text("We'll get back to you quickly.", style: TextStyle(color: BT.mut, fontSize: 13)),

          const SectionLabel("What's it about?"),
          Wrap(spacing: 9, runSpacing: 9, children: _cats.map((c) {
            final on = _category == c[0];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _category = c[0]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(color: on ? BT.ink : BT.card, borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? BT.ink : BT.line)),
                child: Text(c[1], style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : BT.mut)),
              ),
            );
          }).toList()),

          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DESCRIBE THE ISSUE', style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(controller: _desc, maxLines: 4,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: BT.ink),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none,
                  hintText: "The TV isn't turning on since morning…", hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w400))),
            ]),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: BT.ink, content: Text('Photo attach — coming soon'))),
            child: Container(height: 50, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.photo_camera_outlined, size: 18, color: BT.ink), SizedBox(width: 8),
                Text('Add a photo', style: TextStyle(fontWeight: FontWeight.w600)),
              ])),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Submit request', icon: Icons.send_rounded, onTap: _submit),
        ],
      )),
    );
  }
}

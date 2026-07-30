import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Service — resolve a ticket (sv3): how it was fixed + a note the client reads.
class ResolveTicketScreen extends ConsumerStatefulWidget {
  final ServiceTicket ticket;
  const ResolveTicketScreen({super.key, required this.ticket});
  @override
  ConsumerState<ResolveTicketScreen> createState() => _ResolveTicketScreenState();
}

class _ResolveTicketScreenState extends ConsumerState<ResolveTicketScreen> {
  final _note = TextEditingController();
  String _type = 'warranty_replace';
  bool _saving = false;
  String? _error;

  static const _options = [
    ['warranty_replace', 'Replaced under warranty', 'Claim raised with the vendor', Icons.verified_rounded],
    ['repair', 'Repaired on-site', 'Technician visit fixed it', Icons.build_rounded],
    ['remote_guide', 'Guided remotely', 'Sorted over a call — no visit needed', Icons.headset_mic_rounded],
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Add a note — the client sees this as the answer to their request.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(serviceRepoProvider).resolve(widget.ticket.id, _type, _note.text.trim());
      ref.invalidate(serviceTicketsProvider);
      ref.invalidate(serviceTicketProvider(widget.ticket.id));
      ref.invalidate(ticketVisitsProvider(widget.ticket.id));
      ref.invalidate(deliveredTrucksProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink,
          content: Text('${widget.ticket.number} resolved — client notified')));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle,
                  border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999),
                border: Border.all(color: BT.line)),
              child: Text(t.number, style: const TextStyle(fontSize: 12.5,
                fontWeight: FontWeight.w600, color: BT.mut))),
          ]),
          const SizedBox(height: 14),
          Text('Resolve ticket', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          Text([
            if (t.description != null && t.description!.isNotEmpty) t.description!,
            if (t.projectCode != null) t.projectCode!,
          ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BT.mut, fontSize: 13)),

          const SectionLabel('Resolution'),
          ..._options.map((o) {
            final on = _type == o[0];
            return Padding(padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _type = o[0] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                  decoration: BoxDecoration(color: on ? BT.card : BT.card2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: on ? BT.ink : BT.line, width: on ? 1.5 : 1)),
                  child: Row(children: [
                    Container(width: 40, height: 40, alignment: Alignment.center,
                      decoration: BoxDecoration(color: on ? BT.lime : BT.card,
                        borderRadius: BorderRadius.circular(12)),
                      child: Icon(o[3] as IconData, size: 19, color: BT.ink)),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o[1] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(o[2] as String, style: const TextStyle(color: BT.mut, fontSize: 12)),
                    ])),
                    if (on) const Icon(Icons.check_circle_rounded, size: 20, color: BT.ink),
                  ]),
                ),
              ));
          }),

          const SectionLabel('What did you do?'),
          Container(
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BT.line)),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(controller: _note, maxLines: 4,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: BT.ink),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none,
                hintText: 'Replaced the TV unit, new serial logged…',
                hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w400))),
          ),
          const SizedBox(height: 6),
          const Padding(padding: EdgeInsets.only(left: 4),
            child: Text('The client gets this as the answer to their request.',
              style: TextStyle(color: BT.mut2, fontSize: 11.5))),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!,
              style: const TextStyle(color: BT.coral, fontSize: 12.5, height: 1.35))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Mark resolved & notify client', icon: Icons.check_rounded,
                onTap: _submit),
        ],
      )),
    );
  }
}

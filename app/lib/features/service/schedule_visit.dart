import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Service — schedule a technician visit (sv4): who goes, when, and what to know.
class ScheduleVisitScreen extends ConsumerStatefulWidget {
  final ServiceTicket ticket;
  const ScheduleVisitScreen({super.key, required this.ticket});
  @override
  ConsumerState<ScheduleVisitScreen> createState() => _ScheduleVisitScreenState();
}

class _ScheduleVisitScreenState extends ConsumerState<ScheduleVisitScreen> {
  final _note = TextEditingController();
  String? _technicianId;
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  bool _saving = false;
  String? _error;

  static final _dayFmt = DateFormat('EEE d MMM');

  @override
  void initState() {
    super.initState();
    _technicianId = widget.ticket.assignedTo;   // default to whoever owns it
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime get _when =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _submit() async {
    if (_technicianId == null) {
      setState(() => _error = 'Pick who is going.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(serviceRepoProvider).scheduleVisit(
        ticketId: widget.ticket.id, technicianId: _technicianId!,
        when: _when, note: _note.text);
      ref.invalidate(ticketVisitsProvider(widget.ticket.id));
      ref.invalidate(serviceTicketProvider(widget.ticket.id));
      ref.invalidate(serviceTicketsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink,
          content: Text('Visit booked — technician and client notified')));
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
    final techs = ref.watch(techniciansProvider);
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
          Text('Schedule visit', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 12),

          // where + what
          AppCard(padding: const EdgeInsets.all(16), child: Row(children: [
            Container(width: 42, height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.coral, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.local_shipping_rounded, size: 20, color: BT.ink)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([t.clientName, t.projectCode].where((s) => s != null).join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(t.description ?? t.category, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BT.mut, fontSize: 12)),
            ])),
          ])),

          const SectionLabel('Assign technician'),
          techs.when(
            loading: () => const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: BT.ink))),
            error: (e, _) => Text('Could not load the team.\n${friendlyError(e)}',
              style: const TextStyle(color: BT.coral, fontSize: 13)),
            data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.people_outline_rounded, tint: BT.coral,
                  title: 'No technicians',
                  subtitle: 'Add service or workshop members first.')
              : Column(children: list.map((m) {
                  final on = _technicianId == m.id;
                  return Padding(padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _technicianId = m.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: BT.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: on ? BT.ink : BT.line, width: on ? 1.5 : 1)),
                        child: Row(children: [
                          Container(width: 40, height: 40, alignment: Alignment.center,
                            decoration: BoxDecoration(color: roleColor(m.role), shape: BoxShape.circle),
                            child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: BT.ink))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name.isEmpty ? m.email : m.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 1),
                              Text(m.role == 'service' ? 'Service' : 'Workshop technician',
                                style: const TextStyle(color: BT.mut, fontSize: 12)),
                            ])),
                          if (on) const Icon(Icons.check_circle_rounded, size: 20, color: BT.ink),
                        ]),
                      ),
                    ));
                }).toList()),
          ),

          const SectionLabel('When'),
          Row(children: [
            Expanded(child: _picker('Date', _dayFmt.format(_date), Icons.calendar_today_rounded,
              () async {
                final d = await showDatePicker(context: context, initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 180)));
                if (d != null) setState(() => _date = d);
              })),
            const SizedBox(width: 11),
            Expanded(child: _picker('Time', _time.format(context), Icons.schedule_rounded,
              () async {
                final tp = await showTimePicker(context: context, initialTime: _time);
                if (tp != null) setState(() => _time = tp);
              })),
          ]),

          const SectionLabel('Note for the technician'),
          Container(
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BT.line)),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(controller: _note, maxLines: 3,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: BT.ink),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none,
                hintText: 'Carry a spare panel and the warranty card…',
                hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w400))),
          ),

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!,
              style: const TextStyle(color: BT.coral, fontSize: 12.5, height: 1.35))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Confirm visit', icon: Icons.event_available_rounded, onTap: _submit),
        ],
      )),
    );
  }

  Widget _picker(String label, String value, IconData icon, VoidCallback onTap) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BT.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: BT.mut, fontSize: 11)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
            Icon(icon, size: 15, color: BT.mut2),
          ]),
        ]),
      ),
    );
}

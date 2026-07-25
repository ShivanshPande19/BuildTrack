import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — create a member (auth user + profile + role) via the Edge Function.
/// Matches the "New member" mockup: name, email/phone, role chips, Send invite.
/// role=client also creates a client_account (shown then in onboarding).
class AddMember extends ConsumerStatefulWidget {
  const AddMember({super.key});
  @override
  ConsumerState<AddMember> createState() => _AddMemberState();
}

class _AddMemberState extends ConsumerState<AddMember> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _business = TextEditingController();
  String _role = 'procurement';
  bool _saving = false;
  String? _error;

  // Order matches the mockup; Admin added at the end for completeness.
  static const _roles = [
    ['pm', 'Project Manager'], ['procurement', 'Procurement'], ['workshop', 'Workshop'],
    ['design', 'Design'], ['store', 'Store / Inventory'], ['service', 'Service'],
    ['client', 'Client'], ['admin', 'Admin'],
  ];

  String _genPassword() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return 'Az${List.generate(8, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Full name and email are required.');
      return;
    }
    if (_role == 'client' && _business.text.trim().isEmpty) {
      setState(() => _error = 'Business name is required for a client.');
      return;
    }
    final tempPass = _genPassword();
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(adminRepoProvider).createMember(
        fullName: _name.text.trim(), email: _email.text.trim(), password: tempPass,
        phone: null, role: _role,
        businessName: _business.text.trim().isEmpty ? null : _business.text.trim());
      ref.invalidate(membersProvider);
      if (_role == 'client') ref.invalidate(clientsProvider);
      if (!mounted) return;
      await _showCredentials(_email.text.trim(), tempPass);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showCredentials(String email, String pass) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Member created', style: display(19, w: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_name.text.trim()} can sign in with:',
          style: const TextStyle(fontSize: 13.5, color: BT.mut)),
        const SizedBox(height: 12),
        _cred('EMAIL', email),
        const SizedBox(height: 8),
        _cred('TEMP PASSWORD', pass),
        const SizedBox(height: 12),
        const Text('Share these. They can change the password later.',
          style: TextStyle(fontSize: 11.5, color: BT.mut2)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Done', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w600))),
      ],
    ),
  );

  Widget _cred(String label, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      SelectableText(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.ink)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          // top row: back circle + step pill
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
              child: const Text('Step 1 of 1', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut)),
            ),
          ]),
          const SizedBox(height: 16),
          Text('New member', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text("Create an ID and assign a role. Their app opens straight to that role's screens.",
            style: TextStyle(color: BT.mut, fontSize: 13, height: 1.35)),
          const SizedBox(height: 20),

          _field('FULL NAME', _name, hint: 'Karan Mehta'),
          const SizedBox(height: 11),
          _field('EMAIL / PHONE', _email, hint: 'karan@azimuth.co',
            keyboard: TextInputType.emailAddress),

          const SectionLabel('Assign role'),
          Wrap(spacing: 9, runSpacing: 9, children: _roles.map(_roleChip).toList()),

          if (_role == 'client') ...[
            const SizedBox(height: 14),
            _field('BUSINESS NAME', _business, hint: 'Chai Point'),
          ],

          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),

          const SizedBox(height: 24),
          _saving
            ? const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(color: BT.ink)))
            : PrimaryButton('Send invite', icon: Icons.send_rounded, onTap: _submit),
        ],
      )),
    );
  }

  Widget _roleChip(List<String> r) {
    final on = _role == r[0];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() { _role = r[0]; _error = null; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: on ? BT.lime : BT.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Colors.transparent : BT.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8,
            decoration: BoxDecoration(color: on ? BT.ink : BT.mut2, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(r[1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BT.ink)),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? keyboard}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: c, keyboardType: keyboard,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
        decoration: InputDecoration(
          isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
          hintText: hint, hintStyle: const TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
      ),
    ]),
  );
}

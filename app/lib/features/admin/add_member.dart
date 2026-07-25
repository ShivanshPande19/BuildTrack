import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — create a member (auth user + profile + role) via the Edge Function.
/// role=client also creates a client_account (shown then in onboarding).
class AddMember extends ConsumerStatefulWidget {
  const AddMember({super.key});
  @override
  ConsumerState<AddMember> createState() => _AddMemberState();
}

class _AddMemberState extends ConsumerState<AddMember> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _business = TextEditingController();
  String _role = 'pm';
  bool _saving = false;
  String? _error;

  static const _roles = [
    ['pm', 'Project Manager'], ['procurement', 'Procurement'], ['workshop', 'Workshop'],
    ['store', 'Store / Inventory'], ['design', 'Design'], ['service', 'Service'],
    ['client', 'Client'], ['admin', 'Admin'],
  ];

  Future<void> _submit() async {
    if (_name.text.isEmpty || _email.text.isEmpty || _password.text.length < 6) {
      setState(() => _error = 'Name, email and a password (6+ chars) are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(adminRepoProvider).createMember(
        fullName: _name.text.trim(), email: _email.text.trim(), password: _password.text,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        role: _role, businessName: _business.text.trim().isEmpty ? null : _business.text.trim());
      ref.invalidate(membersProvider);
      if (_role == 'client') ref.invalidate(clientsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_name.text} added as $_role'), backgroundColor: BT.ink));
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 18)),
          ]),
          Text('New member', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Creates their login and opens the app straight to their role.',
            style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 18),
          _field('Full name', _name),
          _field('Email', _email),
          _field('Temporary password', _password, obscure: true),
          _field('Phone (optional)', _phone),
          const SectionLabel('Assign role'),
          Container(
            decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              isExpanded: true, value: _role,
              items: _roles.map((r) => DropdownMenuItem(value: r[0], child: Text(r[1]))).toList(),
              onChanged: (v) => setState(() => _role = v!),
            )),
          ),
          if (_role == 'client') Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _field('Business name', _business),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 20),
          _saving
            ? const Center(child: CircularProgressIndicator(color: BT.ink))
            : PrimaryButton('Create member', icon: Icons.check, onTap: _submit),
        ],
      )),
    );
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Container(
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(controller: c, obscureText: obscure,
        decoration: InputDecoration(labelText: label, border: InputBorder.none,
          labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
    ),
  );
}

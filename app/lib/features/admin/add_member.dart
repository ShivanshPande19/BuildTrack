import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Admin — create a member (auth user + profile + role) via the Edge Function.
/// Admin sets the email and password directly (no auto-generated temp password
/// / invite step) — the member signs in with exactly what the admin typed.
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
  final _business = TextEditingController();
  String _role = 'procurement';
  String? _subTeamId;
  bool _saving = false;
  bool _showPass = false;
  String? _error;

  // Order matches the mockup; Admin added at the end for completeness.
  static const _roles = [
    ['pm', 'Project Manager'], ['procurement', 'Procurement'], ['workshop', 'Workshop'],
    ['design', 'Design'], ['store', 'Store / Inventory'], ['service', 'Service'],
    ['client', 'Client'], ['admin', 'Admin'],
  ];

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Full name and email are required.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Set a password of at least 6 characters.');
      return;
    }
    if (_role == 'client' && _business.text.trim().isEmpty) {
      setState(() => _error = 'Business name is required for a client.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(adminRepoProvider).createMember(
        fullName: _name.text.trim(), email: _email.text.trim(),
        phone: null, role: _role, password: _password.text,
        businessName: _business.text.trim().isEmpty ? null : _business.text.trim(),
        subTeamId: _subTeamId);
      ref.invalidate(membersProvider);
      if (_role == 'client') ref.invalidate(clientsProvider);
      if (!mounted) return;
      await _showCredentials(_email.text.trim(), _password.text);
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
        Text('${_name.text.trim()} can sign in with:', style: const TextStyle(fontSize: 13.5, color: BT.mut)),
        const SizedBox(height: 12),
        _cred('EMAIL', email),
        const SizedBox(height: 8),
        _cred('PASSWORD', pass),
        const SizedBox(height: 12),
        const Text('Share these securely. They can change the password later.',
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
          _field('EMAIL', _email, hint: 'karan@azimuth.co',
            keyboard: TextInputType.emailAddress),
          const SizedBox(height: 11),
          _passwordField(),

          const SectionLabel('Assign role'),
          Wrap(spacing: 9, runSpacing: 9, children: _roles.map(_roleChip).toList()),

          // Sub-team within the department (optional — small departments have none).
          if (_role != 'client' && _role != 'admin') _subTeamSection(),

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
            : PrimaryButton('Create member', icon: Icons.check, onTap: _submit),
        ],
      )),
    );
  }

  String _deptLabel(String role) =>
      _roles.firstWhere((r) => r[0] == role, orElse: () => [role, role])[1];

  Widget _subTeamSection() {
    final all = ref.watch(subTeamsProvider).valueOrNull ?? [];
    final teams = all.where((t) => t.role == _role).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Team (optional)'),
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text('Sub-team within ${_deptLabel(_role)} — e.g. Welding, Paint. Skip if there are none.',
          style: const TextStyle(color: BT.mut, fontSize: 12, height: 1.35))),
      Wrap(spacing: 9, runSpacing: 9, children: [
        for (final t in teams) _subTeamChip(t.id, t.name),
        _addTeamChip(),
      ]),
    ]);
  }

  Widget _subTeamChip(String id, String name) {
    final on = _subTeamId == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _subTeamId = on ? null : id),
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
          Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BT.ink)),
        ]),
      ),
    );
  }

  Widget _addTeamChip() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _addSubTeamDialog,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BT.line)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add_rounded, size: 16, color: BT.ink), SizedBox(width: 6),
        Text('New team', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BT.ink)),
      ]),
    ),
  );

  Future<void> _addSubTeamDialog() async {
    final c = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (dctx) => AlertDialog(
      backgroundColor: BT.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('New team in ${_deptLabel(_role)}', style: display(18, w: FontWeight.w600)),
      content: Container(decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(controller: c, autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Welding', border: InputBorder.none))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel', style: TextStyle(color: BT.mut))),
        TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()),
          child: const Text('Add', style: TextStyle(color: BT.ink, fontWeight: FontWeight.w700))),
      ],
    ));
    if (name == null || name.isEmpty) return;
    try {
      final created = await ref.read(adminRepoProvider).createSubTeam(_role, name);
      ref.invalidate(subTeamsProvider);
      if (mounted) setState(() => _subTeamId = created.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.coral, content: Text('Could not add team: $e')));
      }
    }
  }

  Widget _roleChip(List<String> r) {
    final on = _role == r[0];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() { _role = r[0]; _subTeamId = null; _error = null; }),
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

  Widget _passwordField() => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('PASSWORD', style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: BT.mut, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: TextField(
          controller: _password, obscureText: !_showPass,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: BT.ink),
          decoration: const InputDecoration(
            isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero,
            hintText: 'At least 6 characters', hintStyle: TextStyle(color: BT.mut2, fontWeight: FontWeight.w500)),
        )),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showPass = !_showPass),
          child: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 19, color: BT.mut2),
        ),
      ]),
    ]),
  );

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

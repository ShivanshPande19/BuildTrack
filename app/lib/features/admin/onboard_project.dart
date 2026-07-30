import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'create_template.dart';

/// Admin — Onboard a new project (step 1 + 2 of the build chain).
///
/// Creates the build, generates its stages + backward-scheduled dates via
/// fn_onboard_project, and hands it to a project manager.
///
/// A project manager is **required**, not optional: a build with no PM is
/// stranded — it shows up in no PM's list, its stages can never be assigned, and
/// any work submitted against it can never be approved. The client can also be
/// created right here, login included, so the account is always reachable.
class OnboardProject extends ConsumerStatefulWidget {
  const OnboardProject({super.key});
  @override
  ConsumerState<OnboardProject> createState() => _OnboardProjectState();
}

class _OnboardProjectState extends ConsumerState<OnboardProject> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  OptRef? _template, _client, _pm;
  DateTime? _target;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final missing = <String>[
      if (_code.text.trim().isEmpty) 'project code',
      if (_name.text.trim().isEmpty) 'truck name',
      if (_template == null) 'workflow template',
      if (_pm == null) 'project manager',
      if (_target == null) 'delivery date',
    ];
    if (missing.isNotEmpty) {
      setState(() => _error = 'Still needed: ${missing.join(', ')}.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(adminRepoProvider).onboard(
        code: _code.text.trim(), name: _name.text.trim(),
        templateId: _template!.id, clientId: _client?.id, pmId: _pm!.id, target: _target!);
      ref.invalidate(fleetProvider);
      ref.invalidate(allProjectsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: BT.ink,
          content: Text('${_code.text.trim()} onboarded and assigned to ${_pm!.label}')));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _newTemplate() async {
    final created = await Navigator.push<OptRef>(
      context, MaterialPageRoute(builder: (_) => const CreateTemplate()));
    if (created != null && mounted) {
      ref.invalidate(templatesProvider);
      setState(() => _template = created);
    }
  }

  /// Create the client's account + login in one go, then select it.
  Future<void> _newClient() async {
    final created = await showModalBottomSheet<OptRef>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => const _NewClientSheet(),
    );
    if (created != null && mounted) {
      ref.invalidate(clientsProvider);
      ref.invalidate(membersProvider);
      ref.invalidate(loginlessClientsProvider);
      setState(() => _client = created);
    }
  }

  Widget _newBtn(VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GestureDetector(onTap: onTap, child: Container(
      height: 52, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center,
      decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(14)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add, size: 16, color: Colors.white),
        SizedBox(width: 4),
        Text('New', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    )),
  );

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider);
    final clients = ref.watch(clientsProvider);
    final pms = ref.watch(pmsProvider);
    final noPmYet = (pms.valueOrNull ?? const <OptRef>[]).isEmpty && !pms.isLoading;
    final loginless = ref.watch(loginlessClientsProvider).valueOrNull ?? 0;

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
          const Text('Creates the build, schedules its stages and hands it to a PM.',
            style: TextStyle(color: BT.mut, fontSize: 13)),
          const SizedBox(height: 20),
          _text('Project code', _code, hint: 'AZ-142'),
          _text('Truck name', _name, hint: 'Juice Express'),
          Row(children: [
            Expanded(child: _dropdown('Workflow template', templates, _template, (v) => setState(() => _template = v))),
            const SizedBox(width: 8),
            _newBtn(_newTemplate),
          ]),

          // ── client (+ create its login inline) ──
          Row(children: [
            Expanded(child: _dropdown('Client', clients, _client, (v) => setState(() => _client = v))),
            const SizedBox(width: 8),
            _newBtn(_newClient),
          ]),
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 12, top: 2),
            child: Text(
              loginless > 0
                ? '＋ New creates the client\'s account and login together. '
                  '($loginless older client record${loginless == 1 ? '' : 's'} '
                  'without a login ${loginless == 1 ? 'is' : 'are'} hidden — '
                  'they could never sign in to see the build.)'
                : '＋ New creates the client\'s account and login together, so they '
                  'can sign in and follow this build.',
              style: const TextStyle(color: BT.mut2, fontSize: 11.5, height: 1.35)),
          ),

          // ── project manager (required) ──
          _dropdown('Project manager', pms, _pm, (v) => setState(() => _pm = v)),
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 12, top: 2),
            child: Text(
              noPmYet
                ? 'No project managers yet — add one under Team → Add member (role: PM) first.'
                : 'Required. The PM assigns this build\'s stages and approves the work.',
              style: TextStyle(color: noPmYet ? BT.coral : BT.mut2, fontSize: 11.5, height: 1.35)),
          ),

          _dateField(),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline_rounded, size: 15, color: BT.coral),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!,
                style: const TextStyle(color: BT.coral, fontSize: 12.5, height: 1.35))),
            ])),
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

  Widget _dropdown(String label, AsyncValue<List<OptRef>> options, OptRef? value, ValueChanged<OptRef?> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: options.when(
        loading: () => const Padding(padding: EdgeInsets.all(14), child: Text('Loading…', style: TextStyle(color: BT.mut))),
        error: (e, _) => Padding(padding: const EdgeInsets.all(14), child: Text('Error loading $label', style: const TextStyle(color: BT.coral))),
        data: (list) => DropdownButtonHideUnderline(child: DropdownButton<OptRef>(
          isExpanded: true, value: list.contains(value) ? value : null,
          hint: Text(label, style: const TextStyle(color: BT.mut, fontSize: 14)),
          items: list.map((r) => DropdownMenuItem(value: r, child: Text(r.label, overflow: TextOverflow.ellipsis))).toList(),
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

/// Creates a client_account **and** its login together, so the account is never
/// left unreachable. Pops the created option so the caller can select it.
class _NewClientSheet extends ConsumerStatefulWidget {
  const _NewClientSheet();
  @override
  ConsumerState<_NewClientSheet> createState() => _NewClientSheetState();
}

class _NewClientSheetState extends ConsumerState<_NewClientSheet> {
  final _business = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _setPassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _business.dispose(); _contact.dispose(); _email.dispose();
    _phone.dispose(); _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final business = _business.text.trim();
    final email = _email.text.trim();
    if (business.isEmpty || email.isEmpty) {
      setState(() => _error = 'Business name and email are required.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'That email address does not look right.');
      return;
    }
    if (_setPassword && _password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final created = await ref.read(adminRepoProvider).createClientLogin(
        businessName: business,
        email: email,
        contactName: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        password: _setPassword ? _password.text : null,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool obscure = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: BT.line)),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(controller: c, obscureText: obscure,
        decoration: InputDecoration(labelText: label, hintText: hint, border: InputBorder.none,
          labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: const BoxDecoration(color: BT.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: BT.mut2, borderRadius: BorderRadius.circular(2)))),
          Text('New client', style: display(21, w: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Creates their account and their login, so they can follow this build.',
            style: TextStyle(color: BT.mut, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 16),
          _field('Business name', _business, hint: 'Chai Point'),
          _field('Contact person (optional)', _contact, hint: 'Ramesh Kumar'),
          _field('Login email', _email, hint: 'ramesh@chaipoint.in'),
          _field('Phone (optional)', _phone, hint: '+91 90000 00001'),
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _setPassword = !_setPassword),
            child: Row(children: [
              Icon(_setPassword ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 20, color: BT.ink),
              const SizedBox(width: 8),
              const Expanded(child: Text('Set a password now (otherwise an invite email is sent)',
                style: TextStyle(fontSize: 12.5, color: BT.ink, height: 1.3))),
            ]),
          ),
          const SizedBox(height: 10),
          if (_setPassword) _field('Password', _password, hint: 'at least 6 characters', obscure: true),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5, height: 1.35))),
          const SizedBox(height: 4),
          _busy
            ? const Center(child: Padding(padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: BT.ink)))
            : Row(children: [
                Expanded(child: PrimaryButton('Cancel', bg: BT.card2,
                  onTap: () => Navigator.pop(context))),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton('Create client', icon: Icons.person_add_alt_1_rounded,
                  onTap: _create)),
              ]),
        ]),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Where an invited member lands after tapping the email link.
/// They pick their own password; then the app opens to their role.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});
  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (_pass.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_pass.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // Set password + clear the "needs_password" flag so the gate lets them in.
      await sb.auth.updateUser(UserAttributes(
        password: _pass.text,
        data: {'needs_password': false},
      ));
      // Best-effort: flip profile status invited → active (non-critical).
      final uid = sb.auth.currentUser?.id;
      if (uid != null) {
        try { await sb.from('profiles').update({'status': 'active'}).eq('id', uid); } catch (_) {}
      }
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = 'Could not set password. The link may have expired — ask your admin to re-invite.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = sb.auth.currentUser?.userMetadata?['full_name'] as String?;
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 64, height: 64,
            decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.lock_rounded, color: BT.lime, size: 30)),
          const SizedBox(height: 18),
          Text('Set your password', style: display(26, w: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            name != null && name.isNotEmpty
              ? 'Welcome, $name! Choose a password to finish setting up your account.'
              : 'Choose a password to finish setting up your account.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: BT.mut, fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 26),
          _field('New password', _pass),
          const SizedBox(height: 11),
          _field('Confirm password', _confirm),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: BT.coral, fontSize: 12.5))),
          const SizedBox(height: 20),
          _loading
            ? const CircularProgressIndicator(color: BT.ink)
            : PrimaryButton('Save & continue', icon: Icons.arrow_forward_rounded, onTap: _save),
        ]),
      ))),
    );
  }

  Widget _field(String label, TextEditingController c) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: TextField(controller: c, obscureText: true,
      decoration: InputDecoration(labelText: label, border: InputBorder.none,
        labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
  );
}

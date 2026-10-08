import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await sb.auth.signInWithPassword(email: _email.text.trim(), password: _pass.text);
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      Haptic.tap();
      setState(() => _error = 'Sign in failed. Check your credentials.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      // First impression: the mark settles in, then the form, then the button,
      // in one short cascade.
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FadeSlideIn(child: Column(children: [
          Container(width: 64, height: 64,
            decoration: BoxDecoration(color: BT.ink, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.home_work_rounded, color: BT.lime, size: 32)),
          const SizedBox(height: 18),
          Text('BuildTrack', style: display(30)),
          const SizedBox(height: 6),
          const Text('Sign in to manage your builds', style: TextStyle(color: BT.mut, fontSize: 13.5)),
        ])),
        const SizedBox(height: 28),
        FadeSlideIn(delay: Motion.stagger(1, stepMs: 70), child: Column(children: [
          _field('Email', _email),
          const SizedBox(height: 11),
          _field('Password', _pass, obscure: true),
        ])),
        // The error grows into place instead of shoving the button down.
        AnimatedSize(
          duration: Motion.base, curve: Motion.move, alignment: Alignment.topCenter,
          child: _error == null ? const SizedBox(width: double.infinity) : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FadeSlideIn(offsetY: 4, scale: false,
              child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))))),
        const SizedBox(height: 18),
        FadeSlideIn(delay: Motion.stagger(2, stepMs: 70),
          child: PrimaryButton('Sign in', icon: Icons.arrow_forward_rounded, onTap: _signIn, busy: _loading)),
      ]),
    ))),
  );

  Widget _field(String label, TextEditingController c, {bool obscure = false}) => Container(
    decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: BT.line)),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: TextField(controller: c, obscureText: obscure,
      decoration: InputDecoration(labelText: label, border: InputBorder.none,
        labelStyle: const TextStyle(color: BT.mut, fontSize: 12))),
  );
}

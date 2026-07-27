import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Profile / Settings (a9): identity card, settings rows and log out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _roleLabel = {
    'admin': 'Owner · Admin', 'pm': 'Project Manager', 'procurement': 'Procurement',
    'workshop': 'Workshop Lead', 'store': 'Store / Inventory', 'design': 'Design',
    'service': 'Service', 'client': 'Client',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = sb.auth.currentUser;
    final name = (u?.userMetadata?['full_name'] as String?)
        ?? u?.email?.split('@').first ?? 'User';
    final email = u?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final roleAsync = ref.watch(myRoleProvider);

    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: BT.ink)),
            ),
            Text('Profile', style: display(19, w: FontWeight.w600)),
            const SizedBox(width: 42),
          ]),
          const SizedBox(height: 18),

          // identity card
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Column(children: [
              Container(width: 74, height: 74, alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFCFB6EF), Color(0xFFA9D9EF)])),
                child: Text(initial, style: display(26, w: FontWeight.w600, c: const Color(0xFF2A2438)))),
              const SizedBox(height: 14),
              Text(name, style: display(20, w: FontWeight.w600)),
              const SizedBox(height: 8),
              roleAsync.when(
                data: (r) => StatusPill(_roleLabel[r] ?? 'Team member', color: BT.ink, dark: true),
                loading: () => Container(width: 116, height: 30,
                  decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(999))),
                error: (_, __) => const StatusPill('Team member', color: BT.ink, dark: true),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(email, style: const TextStyle(color: BT.mut, fontSize: 12.5)),
              ],
            ]),
          ),

          const SectionLabel('Settings'),
          _setRow(context, Icons.person_outline_rounded, 'Account details'),
          _setRow(context, Icons.home_work_outlined, 'Company profile'),
          _setRow(context, Icons.shield_outlined, 'Roles & permissions'),

          const SizedBox(height: 24),
          _logoutRow(context),
        ],
      )),
    );
  }

  Widget _setRow(BuildContext context, IconData icon, String label) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: BT.ink, content: Text('$label — coming soon'))),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 19, color: BT.ink)),
        const SizedBox(width: 15),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right_rounded, size: 20, color: BT.mut2),
      ]),
    ),
  );

  Widget _logoutRow(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => sb.auth.signOut().then((_) {
      if (context.mounted) context.go('/login');
    }),
    child: Row(children: [
      Container(width: 40, height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFFBE4E0), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.logout_rounded, size: 19, color: BT.coral)),
      const SizedBox(width: 15),
      const Text('Log out', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: BT.coral)),
    ]),
  );
}

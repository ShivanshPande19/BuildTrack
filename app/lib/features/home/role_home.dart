import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// After login the app routes here and renders the shell for the user's role.
/// The 72 designed screens plug into each role's shell (Phase-1 build).
class RoleHome extends StatelessWidget {
  const RoleHome({super.key});

  static const _titles = {
    'admin': 'Fleet Monitor', 'pm': 'My Builds', 'procurement': 'To Order',
    'workshop': 'My Tasks', 'store': 'Inbox', 'design': 'My Designs',
    'service': 'Tickets', 'client': 'My Trucks',
  };
  static const _navs = {
    'admin':       [Icons.home_rounded, Icons.grid_view_rounded, Icons.people_rounded, Icons.bar_chart_rounded],
    'pm':          [Icons.home_rounded, Icons.grid_view_rounded, Icons.calendar_today_rounded, Icons.people_rounded],
    'procurement': [Icons.home_rounded, Icons.receipt_long_rounded, Icons.inventory_2_rounded, Icons.storefront_rounded],
    'workshop':    [Icons.checklist_rounded, Icons.inventory_2_rounded, Icons.calendar_today_rounded, Icons.person_rounded],
    'store':       [Icons.inbox_rounded, Icons.layers_rounded, Icons.inventory_2_rounded, Icons.person_rounded],
    'design':      [Icons.home_rounded, Icons.photo_library_rounded, Icons.verified_rounded, Icons.person_rounded],
    'service':     [Icons.headset_mic_rounded, Icons.local_shipping_rounded, Icons.shield_rounded, Icons.person_rounded],
    'client':      [Icons.local_shipping_rounded, Icons.photo_rounded, Icons.description_rounded, Icons.chat_rounded],
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: fetchMyRole(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator(color: BT.ink)));
        final role = snap.data ?? 'client';
        final title = _titles[role] ?? 'Home';
        final nav = _navs[role] ?? _navs['client']!;
        return Scaffold(
          body: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(role.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.6, color: BT.mut, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(title, style: display(29, w: FontWeight.w500)),
                ]),
                GestureDetector(onTap: () => sb.auth.signOut().then((_) => context.go('/login')),
                  child: CircleAvatar(radius: 21, backgroundColor: roleColor(role),
                    child: Text(role[0].toUpperCase(), style: display(16, c: role == 'admin' ? BT.lime : BT.ink)))),
              ]),
              const SizedBox(height: 24),
              AppCard(color: BT.card,
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: BT.lime),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Signed in as $role. This role shell is wired — the designed screens plug in here.',
                    style: const TextStyle(fontSize: 13, color: BT.mut))),
                ])),
              const Spacer(),
            ]),
          )),
          bottomNavigationBar: PillNav(icons: nav, active: 0, activeLabel: title.split(' ').first),
        );
      },
    );
  }
}

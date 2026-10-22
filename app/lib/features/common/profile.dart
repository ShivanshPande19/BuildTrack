import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import '../admin/company_settings.dart';
import '../admin/workflows_screen.dart';
import 'account_details.dart';
import 'notifications.dart';
import 'roles_reference.dart';

/// Profile / Settings (a9): identity card, settings rows and log out.
///
/// Every row here goes somewhere. They used to be three labels that answered a
/// tap with a "coming soon" snackbar, which is worse than not listing them:
/// Company details, the one setting that genuinely existed, was buried at the
/// bottom of the Team screen under "Workspace" — a people list — where nobody
/// looked for it. It belongs in Settings, so that is where it is now.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _roleLabel = {
    'admin': 'Owner · Admin', 'pm': 'Project Manager', 'procurement': 'Procurement',
    'workshop': 'Workshop', 'store': 'Store / Inventory', 'design': 'Design',
    'service': 'Service', 'client': 'Client',
  };

  /// The pill under the name. Every workshop member used to be called
  /// "Workshop Lead", fitters included. The lead is the supervisor (0032) —
  /// the one a PM hands workshop work to — so they are the one called that,
  /// by the designation the admin gave them if there is one, exactly as the
  /// line under their name in Team reads.
  static String roleLabel(String? role, {MyProfile? me}) {
    if (role == 'workshop' && me != null && me.isSupervisor) {
      return me.designation ?? 'Workshop Supervisor';
    }
    return _roleLabel[role] ?? 'Team member';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = sb.auth.currentUser;
    final me = ref.watch(myProfileProvider).valueOrNull;
    // profiles.full_name first: it is the name Account details edits. The
    // auth metadata only carries a name when the account was made from Add
    // member; the owner's own account was not, so their card showed the
    // email prefix — "admin".
    final metaName = (u?.userMetadata?['full_name'] as String?)?.trim();
    final name = (me != null && me.name.trim().isNotEmpty)
        ? me.name.trim()
        : (metaName != null && metaName.isNotEmpty)
            ? metaName
            : u?.email?.split('@').first ?? 'User';
    final email = u?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final roleAsync = ref.watch(myRoleProvider);

    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const BackChip(),
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
                data: (r) => StatusPill(roleLabel(r, me: me), color: BT.ink, dark: true),
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
          _setRow(context, Icons.notifications_none_rounded, 'Notifications',
            subtitle: 'Everything the app has told you',
            open: () => const NotificationsScreen()),
          _setRow(context, Icons.person_outline_rounded, 'Account details',
            subtitle: 'Your name, number and what your admin set',
            open: () => const AccountDetailsScreen()),
          // Admin edits the buyer block; everyone else can see what is printed
          // on the purchase orders they handle, read-only.
          roleAsync.when(
            data: (r) => _setRow(context, Icons.home_work_outlined, 'Company details',
              subtitle: r == 'admin'
                ? 'Buyer name, GSTIN and state on every purchase order'
                : 'What is printed on every purchase order',
              open: () => const CompanySettingsScreen()),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // The people who plan builds keep their workflows here.
          roleAsync.when(
            data: (r) => r == 'admin' || r == 'pm'
              ? _setRow(context, Icons.account_tree_outlined, 'Workflows',
                  subtitle: 'How a build runs, stage by stage',
                  open: () => const WorkflowsScreen())
              : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          _setRow(context, Icons.shield_outlined, 'Roles & permissions',
            subtitle: 'What each role can and cannot do',
            open: () => const RolesReferenceScreen()),

          const SizedBox(height: 24),
          _logoutRow(context),
        ],
      )),
    );
  }

  Widget _setRow(BuildContext context, IconData icon, String label,
      {required Widget Function() open, String? subtitle}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => open())),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 19, color: BT.ink)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: BT.mut)),
          ],
        ])),
        const SizedBox(width: 8),
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

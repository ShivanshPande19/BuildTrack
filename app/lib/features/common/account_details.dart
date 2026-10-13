import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';

/// Settings → **Account details**. Your own profile: the two fields that are
/// yours to change, and the ones that are the admin's to set, shown so it is
/// obvious which is which rather than left out.
///
/// This replaced a "coming soon" snackbar. It could not have worked before —
/// `profiles` was admin-write-only, so a member could not save their own name
/// — which 0026 fixes with a self-update policy plus a trigger that keeps role,
/// email, team and status on the admin's side of the line.
class AccountDetailsScreen extends ConsumerStatefulWidget {
  const AccountDetailsScreen({super.key});
  @override
  ConsumerState<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends ConsumerState<AccountDetailsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _seeded = false, _saving = false;
  String? _error;

  static final _joined = DateFormat('d MMM yyyy');
  static const _roleLabel = {
    'admin': 'Owner · Admin', 'pm': 'Project Manager', 'procurement': 'Procurement',
    'workshop': 'Workshop', 'store': 'Store / Inventory', 'design': 'Design',
    'service': 'Service & Support', 'client': 'Client',
  };

  void _seed(MyProfile p) {
    if (_seeded) return;
    _seeded = true;
    _name.text = p.name;
    _phone.text = p.phone ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Your name cannot be empty.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await saveMyProfile(fullName: _name.text, phone: _phone.text);
      ref.invalidate(myProfileProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: BT.ink, content: Text('Your details are saved.')));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider);
    // The header stays outside the async branch, so the screen can always be
    // left — even while it loads, and even if the load fails.
    return Scaffold(
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          const Row(children: [BackChip()]),
          const SizedBox(height: 14),
          Text('Account details', style: display(29, w: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Your name and number, as the rest of the team sees them.',
            style: TextStyle(color: BT.mut, fontSize: 12.5)),
          const SizedBox(height: 20),
          ContentReveal(child: me.when(
            loading: () => const SkeletonList(count: 4, leading: false, trailingPill: false),
            error: (e, _) => ErrorCard('Could not load your details.\n${friendlyError(e)}',
              onRetry: () => ref.invalidate(myProfileProvider)),
            data: (p) {
              if (p == null) {
                return const ErrorCard('You appear to be signed out. Log in again to see this.');
              }
              _seed(p);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LabelledField('FULL NAME', controller: _name, hint: 'Your name'),
                const SizedBox(height: 11),
                LabelledField('PHONE', controller: _phone, hint: '+91 …',
                  keyboardType: TextInputType.phone),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
                  child: Text(_error!, style: const TextStyle(color: BT.coral, fontSize: 12.5))),
                const SizedBox(height: 18),
                PrimaryButton('Save', icon: Icons.check, onTap: _save, busy: _saving),

                // Set by the admin, shown so nobody wonders where to change it.
                const SectionLabel('Set by your admin'),
                _readOnly(Icons.badge_outlined, 'Role', _roleLabel[p.role] ?? p.role),
                if (p.subTeamName != null)
                  _readOnly(Icons.groups_outlined, 'Team', p.subTeamName!),
                _readOnly(Icons.alternate_email_rounded, 'Email', p.email),
                _readOnly(Icons.verified_user_outlined, 'Account status',
                  switch (p.status) {
                    'active'   => 'Active',
                    'invited'  => 'Invited — set a password to activate',
                    'disabled' => 'Disabled',
                    _          => p.status,
                  }),
                if (p.createdAt != null)
                  _readOnly(Icons.event_outlined, 'Member since', _joined.format(p.createdAt!)),
                const SizedBox(height: 8),
                const Text('To change your role, email or team, ask an admin — '
                           'those are set on the Team screen.',
                  style: TextStyle(color: BT.mut2, fontSize: 11.5)),
              ]);
            },
          )),
        ],
      )),
    );
  }

  Widget _readOnly(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
    child: Row(children: [
      Container(width: 36, height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: BT.card2, borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, size: 17, color: BT.mut)),
      const SizedBox(width: 13),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: BT.mut))),
      const SizedBox(width: 10),
      Flexible(child: Text(value, textAlign: TextAlign.right, maxLines: 2,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
    ]),
  );
}

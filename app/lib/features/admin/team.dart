import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';
import 'add_member.dart';

/// Admin — Team & roles. Lists members; "+" opens Add Member.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  static const _roleLabel = {
    'admin': 'Admin', 'pm': 'PM', 'procurement': 'Procure', 'workshop': 'Workshop',
    'store': 'Store', 'design': 'Design', 'service': 'Service', 'client': 'Client',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: RefreshIndicator(
        onRefresh: () async => ref.refresh(membersProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 18)),
              const Spacer(),
            ]),
            Text('Team', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 16),
            members.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => AppCard(child: Text('Could not load team.\n$e',
                style: const TextStyle(color: BT.coral, fontSize: 13))),
              data: (list) => Column(children: list.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  child: Row(children: [
                    CircleAvatar(radius: 22, backgroundColor: roleColor(m.role),
                      child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: TextStyle(fontWeight: FontWeight.w700,
                          color: m.role == 'admin' ? BT.lime : BT.ink))),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(m.email, style: const TextStyle(color: BT.mut, fontSize: 12)),
                    ])),
                    StatusPill(_roleLabel[m.role] ?? m.role,
                      color: roleColor(m.role) == BT.ink ? BT.lime : roleColor(m.role),
                      dark: m.role == 'admin'),
                  ]),
                ),
              )).toList()),
            ),
          ],
        ),
      )),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: BT.lime, foregroundColor: BT.ink,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddMember())),
        icon: const Icon(Icons.person_add_alt_1), label: const Text('Add member'),
      ),
    );
  }
}

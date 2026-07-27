import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/widgets.dart';

/// Notifications feed (a8): grouped Today / Earlier, with "Mark all read".
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  ({IconData icon, Color bg, Color fg}) _style(String? type) => switch (type) {
    'order_due' => (icon: Icons.warning_amber_rounded, bg: BT.coral, fg: const Color(0xFF5A2410)),
    'stage_done'=> (icon: Icons.check_rounded, bg: BT.lime, fg: const Color(0xFF3A4A12)),
    'at_risk'   => (icon: Icons.error_outline_rounded, bg: BT.amber, fg: const Color(0xFF4A3410)),
    'po'        => (icon: Icons.receipt_long_rounded, bg: BT.lav, fg: const Color(0xFF3A2A4A)),
    'approved'  => (icon: Icons.verified_rounded, bg: BT.sky, fg: const Color(0xFF1C3A4A)),
    _           => (icon: Icons.notifications_none_rounded, bg: BT.card2, fg: BT.ink),
  };

  String _ago(DateTime? t) {
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  bool _isToday(DateTime? t) {
    if (t == null) return false;
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationsProvider);
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(notificationsProvider.future),
        child: ListView(
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await ref.read(notificationsRepoProvider).markAllRead();
                  ref.invalidate(notificationsProvider);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(color: BT.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: BT.line)),
                  child: const Text('Mark all read', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BT.mut))),
              ),
            ]),
            const SizedBox(height: 14),
            Text('Notifications', style: display(29, w: FontWeight.w500)),
            const SizedBox(height: 4),
            notifs.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: BT.ink))),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 16),
                child: AppCard(child: Text('Could not load notifications.\n$e',
                  style: const TextStyle(color: BT.coral, fontSize: 13)))),
              data: _list,
            ),
          ],
        ),
      )),
    );
  }

  Widget _list(List<AppNotification> all) {
    if (all.isEmpty) {
      return const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState(
        icon: Icons.notifications_none_rounded, tint: BT.sky,
        title: 'No notifications',
        subtitle: "You're all caught up — alerts about orders, stages and approvals show here."));
    }
    final today = all.where((n) => _isToday(n.createdAt)).toList();
    final earlier = all.where((n) => !_isToday(n.createdAt)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (today.isNotEmpty) ...[
        const SectionLabel('Today'),
        ...today.map(_row),
      ],
      if (earlier.isNotEmpty) ...[
        const SectionLabel('Earlier'),
        ...earlier.map(_row),
      ],
    ]);
  }

  Widget _row(AppNotification n) {
    final s = _style(n.type);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(s.icon, size: 19, color: s.fg)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n.title, style: TextStyle(fontSize: 13.5, height: 1.35,
            fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
          if (n.body != null && n.body!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(n.body!, style: const TextStyle(fontSize: 12, color: BT.mut, height: 1.3)),
          ],
          const SizedBox(height: 3),
          Text(_ago(n.createdAt), style: const TextStyle(fontSize: 11, color: BT.mut2)),
        ])),
        if (!n.read) Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6, left: 6),
          decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)),
      ]),
    );
  }
}

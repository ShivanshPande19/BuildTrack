import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../shared/animations.dart';
import '../../shared/widgets.dart';

/// Notifications feed: grouped Today / Earlier, with "Mark all read".
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // Set while "Mark all read" runs: unread dots fade out immediately instead of
  // waiting for the round-trip, and a double tap can't fire it twice.
  bool _markingAll = false;

  /// One style per type the backend actually sends (see fn_notify calls in the
  /// migrations). The old map only knew demo types (`order_due`, `po`, …) that
  /// nothing emits, so almost every real notification got the generic bell.
  static ({IconData icon, Color bg, Color fg}) _style(String? type) => switch (type) {
    'stage_done' || 'approved' || 'po_approved' || 'resolved' || 'delivered' =>
      (icon: Icons.check_rounded, bg: BT.lime, fg: const Color(0xFF3A4A12)),
    'stage_assigned' || 'project_assigned' || 'stage_started' =>
      (icon: Icons.assignment_ind_rounded, bg: BT.sky, fg: const Color(0xFF1C3A4A)),
    'stage_submitted' || 'po_approval' =>
      (icon: Icons.pending_actions_rounded, bg: BT.amber, fg: const Color(0xFF4A3410)),
    'rework' || 'revision' || 'po_rejected' =>
      (icon: Icons.replay_rounded, bg: BT.coral, fg: const Color(0xFF5A2410)),
    'recall' || 'order_due' || 'at_risk' =>
      (icon: Icons.warning_amber_rounded, bg: BT.coral, fg: const Color(0xFF5A2410)),
    'ticket' || 'visit' =>
      (icon: Icons.support_agent_rounded, bg: BT.lav, fg: const Color(0xFF3A2A4A)),
    'stock_request' || 'po' =>
      (icon: Icons.receipt_long_rounded, bg: BT.lav, fg: const Color(0xFF3A2A4A)),
    'stage_unassigned' || 'project_reassigned' =>
      (icon: Icons.swap_horiz_rounded, bg: BT.card2, fg: BT.ink),
    _ => (icon: Icons.notifications_none_rounded, bg: BT.card2, fg: BT.ink),
  };

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final local = t.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && _isToday(t)) return '${diff.inHours}h ago';
    if (_isYesterday(t)) return 'Yesterday';
    return '${diff.inDays < 1 ? 1 : diff.inDays}d ago';
  }

  // Timestamps arrive in UTC. Compare LOCAL calendar days. Comparing the UTC
  // day put anything between midnight and 05:30 IST into the wrong group.
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static bool _isToday(DateTime? t) => t != null && _sameDay(t.toLocal(), DateTime.now());
  static bool _isYesterday(DateTime? t) =>
      t != null && _sameDay(t.toLocal(), DateTime.now().subtract(const Duration(days: 1)));

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationsRepoProvider).markAllRead();
      Haptic.confirm();
      ref.invalidate(notificationsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: BT.coral, content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifs = ref.watch(notificationsProvider);
    final unread = notifs.valueOrNull?.where((n) => !n.read).length ?? 0;
    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        onRefresh: () async => ref.refresh(notificationsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const BackChip(),
              AnimatedOpacity(
                duration: Motion.fast,
                opacity: unread == 0 && !_markingAll ? 0.45 : 1,
                child: PillAction(_markingAll ? 'Marking…' : 'Mark all read',
                  icon: Icons.done_all_rounded, dark: false,
                  onTap: unread == 0 ? null : _markAll),
              ),
            ]),
            const SizedBox(height: 14),
            FadeSlideIn(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Notifications', style: display(29, w: FontWeight.w500)),
              const SizedBox(width: 10),
              Padding(padding: const EdgeInsets.only(bottom: 6),
                child: BadgePop(visible: unread > 0 && !_markingAll, valueKey: unread,
                  child: StatusPill('$unread new', color: BT.lime))),
            ])),
            const SizedBox(height: 4),
            notifs.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(padding: EdgeInsets.only(top: 12), child: SkeletonList(count: 6)),
              error: (e, _) => Padding(padding: const EdgeInsets.only(top: 16),
                child: ErrorCard('Could not load notifications.\n${friendlyError(e)}',
                  onRetry: () => ref.invalidate(notificationsProvider))),
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
        subtitle: "You're all caught up. Alerts about orders, stages and approvals show here."));
    }
    final today = all.where((n) => _isToday(n.createdAt)).toList();
    final earlier = all.where((n) => !_isToday(n.createdAt)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: staggered([
      if (today.isNotEmpty) ...[
        const SectionLabel('Today'),
        ...today.map(_row),
      ],
      if (earlier.isNotEmpty) ...[
        const SectionLabel('Earlier'),
        ...earlier.map(_row),
      ],
    ], stepMs: 30));
  }

  Widget _row(AppNotification n) {
    final s = _style(n.type);
    final unread = !n.read && !_markingAll;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BT.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(s.icon, size: 19, color: s.fg)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedDefaultTextStyle(
            duration: Motion.base,
            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13.5, height: 1.35, color: BT.ink,
              fontWeight: unread ? FontWeight.w700 : FontWeight.w500),
            child: Text(n.title)),
          if (n.body != null && n.body!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(n.body!, style: const TextStyle(fontSize: 12, color: BT.mut, height: 1.3)),
          ],
          const SizedBox(height: 3),
          Text(_ago(n.createdAt), style: const TextStyle(fontSize: 11, color: BT.mut2)),
        ])),
        AnimatedScale(
          duration: Motion.base,
          curve: unread ? Curves.easeOutBack : Motion.exit,
          scale: unread ? 1 : 0,
          child: Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6, left: 6),
            decoration: const BoxDecoration(color: BT.lime, shape: BoxShape.circle)),
        ),
      ]),
    );
  }
}

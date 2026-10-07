import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase_client.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../features/common/notifications.dart';
import '../features/common/profile.dart';
import 'animations.dart';
import 'widgets.dart';

/// The per-role avatar gradient (start, end, initial colour). These are the
/// colours each role home already used, collected in one place.
({List<Color> colors, Color ink}) _avatarStyle(String role) => switch (role) {
      'admin' => (colors: const [Color(0xFFCFB6EF), Color(0xFFA9D9EF)], ink: const Color(0xFF2A2438)),
      'pm' => (colors: const [Color(0xFFA9D9EF), Color(0xFF7FBFE0)], ink: const Color(0xFF123040)),
      'procurement' => (colors: const [Color(0xFFC4A5EC), Color(0xFFA98FE0)], ink: const Color(0xFF31234A)),
      'store' => (colors: const [Color(0xFF9FE0C8), Color(0xFF66C6A4)], ink: const Color(0xFF0F3A2A)),
      'workshop' => (colors: const [Color(0xFFF4D07A), Color(0xFFE9B84A)], ink: const Color(0xFF4A3410)),
      'design' => (colors: const [Color(0xFFF3C3DD), Color(0xFFC4A5EC)], ink: const Color(0xFF4A2438)),
      'service' => (colors: const [Color(0xFFF2A585), Color(0xFFE07F5A)], ink: const Color(0xFF5A2410)),
      _ => (colors: const [Color(0xFFF3C3DD), Color(0xFFF2A585)], ink: const Color(0xFF5A2438)),
    };

/// The shared top of every role's tab: eyebrow + title on the left, the
/// notification bell and profile avatar on the right.
///
/// The bell carries an **unread badge for every role** (it used to be Admin
/// only). The badge pops in and pulses when the count changes. The title
/// cross-fades when the tab changes. [badge] overrides the count (keep it for
/// notifications only, so the bell means the same thing everywhere). Pass
/// [showAvatar] = false for roles whose profile lives in its own tab.
class RoleHeader extends ConsumerWidget {
  final String role;
  final String eyebrow;
  final String title;
  final int? badge;
  final bool showAvatar;
  final bool avatarOpensProfile;
  const RoleHeader({
    super.key,
    required this.role,
    required this.eyebrow,
    required this.title,
    this.badge,
    this.showAvatar = true,
    this.avatarOpensProfile = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = badge ??
        (ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow(eyebrow),
          const SizedBox(height: 2),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(29, w: FontWeight.w500)),
        ]),
      ),
      const SizedBox(width: 12),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          NotifBell(count: unread),
          if (showAvatar) ...[
            const SizedBox(width: 10),
            RoleAvatar(role: role, onTap: avatarOpensProfile
                ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()))
                : null),
          ],
        ]),
      ),
    ]);
  }
}

/// Circle bell that opens the notifications feed. The count badge pops in
/// with a spring and pulses when it changes. Opening the feed and coming back
/// refreshes the count.
class NotifBell extends ConsumerWidget {
  final int count;
  const NotifBell({super.key, required this.count});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
        button: true,
        label: count > 0 ? 'Notifications, $count unread' : 'Notifications',
        child: PressableScale(
          haptic: true,
          pressedScale: 0.88,
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            ref.invalidate(notificationsProvider);
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: BT.card, shape: BoxShape.circle, border: Border.all(color: BT.line)),
              child: const Icon(Icons.notifications_none_rounded, size: 20, color: BT.ink),
            ),
            Positioned(
              top: -3,
              right: -3,
              child: BadgePop(
                visible: count > 0,
                valueKey: count,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 19),
                  height: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: BT.coral,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BT.bg, width: 2)),
                  child: Text(count > 99 ? '99+' : '$count',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF3A1C10))),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// The signed-in user's initial on their role's gradient.
class RoleAvatar extends StatelessWidget {
  final String role;
  final VoidCallback? onTap;
  final double size;
  const RoleAvatar({super.key, required this.role, this.onTap, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final u = sb.auth.currentUser;
    final nm = (u?.userMetadata?['full_name'] as String?) ?? u?.email ?? '';
    final initial = nm.isNotEmpty ? nm[0].toUpperCase() : role[0].toUpperCase();
    final s = _avatarStyle(role);
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.colors),
        boxShadow: [BoxShadow(color: s.colors.last.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Text(initial, style: display(size * 0.36, w: FontWeight.w600, c: s.ink)),
    );
    if (onTap == null) return avatar;
    return Semantics(
      button: true,
      label: 'Profile',
      child: PressableScale(onTap: onTap, haptic: true, pressedScale: 0.88, child: avatar),
    );
  }
}

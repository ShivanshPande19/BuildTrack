import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'supabase_client.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/home/role_home.dart';

final router = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) {
    final loggedIn = sb.auth.currentSession != null;
    final loc = state.matchedLocation;
    final onLogin = loc == '/login';
    final onSetPw = loc == '/set-password';

    if (!loggedIn) return onLogin ? null : '/login';

    // Signed in via an invite / recovery link → force password setup first.
    if (needsPasswordSet()) return onSetPw ? null : '/set-password';

    if (onLogin || onSetPw) return '/home';
    return null;
  },
  refreshListenable: _AuthRefresh(),
  routes: [
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/set-password', builder: (c, s) => const SetPasswordScreen()),
    GoRoute(path: '/home',  builder: (c, s) => const RoleHome()),
  ],
);

/// Rebuild routes when auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    sb.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

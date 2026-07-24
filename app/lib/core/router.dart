import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'supabase_client.dart';
import '../features/auth/login_screen.dart';
import '../features/home/role_home.dart';

final router = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) {
    final loggedIn = sb.auth.currentSession != null;
    final onLogin = state.matchedLocation == '/login';
    if (!loggedIn) return onLogin ? null : '/login';
    if (onLogin) return '/home';
    return null;
  },
  refreshListenable: _AuthRefresh(),
  routes: [
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/home',  builder: (c, s) => const RoleHome()),
  ],
);

/// Rebuild routes when auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    sb.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

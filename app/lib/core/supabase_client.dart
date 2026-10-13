import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase config. In production, inject via --dart-define.
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR-PROJECT.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR-ANON-KEY');

/// Deep link that invite / password-recovery emails redirect back to.
/// Must be registered in: iOS Info.plist + Android manifest + Supabase
/// Dashboard → Authentication → URL Configuration → Redirect URLs.
const inviteRedirectUrl = 'io.supabase.buildtrack://login-callback/';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );
}

SupabaseClient get sb => Supabase.instance.client;

/// True when the signed-in user arrived via an invite / recovery link and
/// still has to choose their own password.
bool needsPasswordSet() =>
    sb.auth.currentUser?.userMetadata?['needs_password'] == true;

/// Fetch the signed-in user's role from `profiles`.
Future<String?> fetchMyRole() async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await sb.from('profiles').select('role').eq('id', uid).maybeSingle();
  return row?['role'] as String?;
}

/// The signed-in user's account status: `active` | `invited` | `disabled`.
///
/// Read at sign-in so a disabled account is told why it cannot get in. Their
/// own row stays readable (`p_profiles_read_self` is `id = auth.uid()`), which
/// is deliberate — it is the one query a disabled user still needs to answer.
Future<String?> fetchMyStatus() async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await sb.from('profiles').select('status').eq('id', uid).maybeSingle();
  return row?['status'] as String?;
}

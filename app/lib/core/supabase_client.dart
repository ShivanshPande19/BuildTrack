import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase config. In production, inject via --dart-define.
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR-PROJECT.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR-ANON-KEY');

Future<void> initSupabase() async {
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

SupabaseClient get sb => Supabase.instance.client;

/// Fetch the signed-in user's role from `profiles`.
Future<String?> fetchMyRole() async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await sb.from('profiles').select('role').eq('id', uid).maybeSingle();
  return row?['role'] as String?;
}

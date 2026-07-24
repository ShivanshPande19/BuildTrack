import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: BuildTrackApp()));
}

class BuildTrackApp extends StatelessWidget {
  const BuildTrackApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Azimuth BuildTrack',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: router,
  );
}

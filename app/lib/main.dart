import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: draw the app behind the system status & navigation bars and
  // make them transparent, so the warm background runs seamlessly to every
  // edge instead of leaving a distinct beige band around a coloured system bar.
  // Dark icons are used since the background is light.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
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
    // No safe-area insets anywhere: zero the padding / viewPadding the whole
    // app sees, so every SafeArea becomes a no-op and content runs fully
    // edge-to-edge. One switch to flip (or revert) app-wide.
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
}

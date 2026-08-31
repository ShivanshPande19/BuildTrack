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
    // Keep the TOP safe-area inset (so content clears the status bar / notch)
    // but run edge-to-edge at the BOTTOM — zero only the bottom padding so the
    // nav sits flush against the bottom edge. Top-only safe area, app-wide.
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(bottom: 0),
          viewPadding: mq.viewPadding.copyWith(bottom: 0),
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
}

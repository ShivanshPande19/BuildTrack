import 'dart:async';
import 'dart:io';
import 'dart:ui';

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

  // Nothing was catching async errors that escape a callback, and one of them
  // escapes routinely: supabase_flutter refreshes the access token on a timer,
  // and on a bad connection that throws AuthRetryableFetchException straight
  // into the zone. A workshop has bad signal by definition.
  //
  // In release that is only noise in the log. In a debug build it is reported
  // as an **unhandled** exception, which pauses the isolate — the Dart thread
  // stops, the UI stops painting, and the app looks frozen with whatever route
  // was on screen stuck there. That is a genuine "the app froze" report that
  // has nothing to do with the screen the person was on.
  //
  // Returning true means "handled": the error is swallowed deliberately,
  // because there is nothing the person can do about a refresh that will be
  // retried anyway, and the screens already say when a read fails. Anything we
  // do not recognise is passed on so it still shows up in development.
  PlatformDispatcher.instance.onError = (error, stack) {
    final text = error.toString();
    final isTransientNetwork = error is SocketException
        || error is TimeoutException
        || text.contains('AuthRetryableFetchException')
        || text.contains('Failed host lookup')
        || text.contains('ClientException');
    if (isTransientNetwork) {
      debugPrint('BuildTrack: ignoring transient network error — $error');
      return true;
    }
    return false;
  };

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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shared/animations.dart';

/// Equora design tokens — the same palette used across all 72 role screens.
class BT {
  static const bg    = Color(0xFFEAE7DB);
  static const card  = Color(0xFFFBFAF5);
  static const card2 = Color(0xFFF3F1E7);
  static const ink   = Color(0xFF1D1C18);
  static const mut   = Color(0xFF918B7C);
  static const mut2  = Color(0xFFB4AE9E);
  static const line  = Color(0xFFE7E3D5);
  static const track = Color(0xFFECE9DD);

  // candy accents
  static const lime  = Color(0xFFCDEC63);
  static const sky   = Color(0xFFA9D9EF);
  static const lav   = Color(0xFFC4A5EC);
  static const pink  = Color(0xFFF3C3DD);
  static const coral = Color(0xFFF2A585);
  static const amber = Color(0xFFF4D07A);
  static const mint  = Color(0xFF9FE0C8);

  static const radiusCard = 24.0;
  static const radiusPill = 999.0;
}

/// Role → accent colour (matches each role's avatar in the UI).
Color roleColor(String role) => switch (role) {
  'admin'       => BT.ink,
  'pm'          => BT.sky,
  'procurement' => BT.lav,
  'workshop'    => BT.amber,
  'store'       => BT.mint,
  'design'      => BT.pink,
  'service'     => BT.coral,
  _             => BT.lime,
};

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: BT.bg,
    colorSchemeSeed: BT.lime,
    brightness: Brightness.light,
  );
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
      .apply(bodyColor: BT.ink, displayColor: BT.ink);
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: BT.bg, foregroundColor: BT.ink, elevation: 0,
      surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0,
    ),
    // iOS keeps the native slide + edge-swipe-back; Android gets M3 fade-forwards
    // with predictive back. See animations.dart → appPageTransitions().
    pageTransitionsTheme: appPageTransitions(),
    // No grey Material ripple splashing over the Equora cards. Taps respond with
    // PressableScale instead; a soft highlight is kept for list tiles.
    splashFactory: NoSplash.splashFactory,
    highlightColor: BT.ink.withValues(alpha: 0.04),
    // Snackbars float as rounded ink pills above the floating nav, never as a
    // full-width bar glued to the screen edge.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BT.ink,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
      actionTextColor: BT.lime,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: BT.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: display(18, w: FontWeight.w600),
      contentTextStyle: text.bodyMedium?.copyWith(color: BT.mut, fontSize: 13.5, height: 1.4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BT.bg,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x661D1C18),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BT.ink, linearTrackColor: BT.track, refreshBackgroundColor: BT.card,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: BT.ink,
      selectionColor: BT.lime.withValues(alpha: 0.6),
      selectionHandleColor: BT.ink,
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: BT.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    )),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: BT.card,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: BT.ink,
      headerForegroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      todayBorder: const BorderSide(color: BT.ink),
      dayShape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
    colorScheme: base.colorScheme.copyWith(primary: BT.ink, onPrimary: Colors.white, surface: BT.bg),
  );
}

/// Space Grotesk for display numbers / headings.
TextStyle display(double size, {FontWeight w = FontWeight.w600, Color? c}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c ?? BT.ink, letterSpacing: -0.5);

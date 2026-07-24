import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: BT.ink, displayColor: BT.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: BT.bg, foregroundColor: BT.ink, elevation: 0,
    ),
  );
}

/// Space Grotesk for display numbers / headings.
TextStyle display(double size, {FontWeight w = FontWeight.w600, Color? c}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c ?? BT.ink, letterSpacing: -0.5);

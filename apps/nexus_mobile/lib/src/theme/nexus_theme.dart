import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NexusPalette {
  NexusPalette._();

  static const darkBg = Color(0xFF05070F);
  static const darkSurface = Color(0xFF0B0E1A);
  static const darkPanel = Color(0xFF111527);
  static const darkBorder = Color(0xFF1D2236);
  static const darkBody = Color(0xFFA8B0CC);
  static const darkBright = Color(0xFFDDE3F5);

  static const lightBg = Color(0xFFF2F5FF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightPanel = Color(0xFFEEF1FB);
  static const lightBorder = Color(0xFFD4DAF0);
  static const lightBody = Color(0xFF363D5C);
  static const lightBright = Color(0xFF0D1128);

  static const cyan = Color(0xFF00C8F0);
  static const violet = Color(0xFF7C6CFA);
  static const amber = Color(0xFFFFB340);
  static const green = Color(0xFF00DFA0);
  static const rose = Color(0xFFFF4F6E);
  static const dim = Color(0xFF6B738F);
}

ThemeData nexusTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: NexusPalette.cyan,
    primary: NexusPalette.cyan,
    secondary: NexusPalette.violet,
    error: NexusPalette.rose,
    surface: isDark ? NexusPalette.darkSurface : NexusPalette.lightSurface,
  );

  final bodyFont = GoogleFonts.dmSansTextTheme();
  final heading = GoogleFonts.syne();
  final mono = GoogleFonts.dmMono();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    drawerTheme: DrawerThemeData(
      backgroundColor: isDark
          ? NexusPalette.darkSurface
          : NexusPalette.lightSurface,
    ),
    scaffoldBackgroundColor: isDark
        ? NexusPalette.darkBg
        : NexusPalette.lightBg,
    textTheme: bodyFont.copyWith(
      headlineLarge: heading.copyWith(fontWeight: FontWeight.w800),
      headlineMedium: heading.copyWith(fontWeight: FontWeight.w800),
      titleLarge: heading.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: GoogleFonts.dmSans(
        color: isDark ? NexusPalette.darkBody : NexusPalette.lightBody,
      ),
      labelLarge: mono.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
      ),
      bodyMedium: GoogleFonts.dmSans(
        color: isDark ? NexusPalette.darkBody : NexusPalette.lightBody,
      ),
      bodySmall: GoogleFonts.dmSans(
        color: isDark ? NexusPalette.darkBody : NexusPalette.lightBody,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? NexusPalette.darkPanel : NexusPalette.lightSurface,
      labelStyle: TextStyle(
        color: isDark ? NexusPalette.darkBody : NexusPalette.lightBody,
      ),
      floatingLabelStyle: TextStyle(
        color: isDark ? NexusPalette.cyan : NexusPalette.violet,
      ),
      hintStyle: TextStyle(
        color: (isDark ? NexusPalette.darkBody : NexusPalette.lightBody)
            .withValues(alpha: 0.75),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder,
        ),
      ),
    ),
  );
}

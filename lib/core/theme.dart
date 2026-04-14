import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Nunito font system:
  //   Headings / Titles  → Nunito Bold (700–800)
  //   Body / Notes        → Nunito Regular (400–500)
  //   Labels / Small text → Nunito SemiBold (600)
  static final TextTheme _textTheme = TextTheme(
    displayLarge: GoogleFonts.nunito(fontSize: 57, fontWeight: FontWeight.w800),
    displayMedium: GoogleFonts.nunito(
      fontSize: 45,
      fontWeight: FontWeight.w700,
    ),
    displaySmall: GoogleFonts.nunito(fontSize: 36, fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.nunito(
      fontSize: 32,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: GoogleFonts.nunito(
      fontSize: 28,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: GoogleFonts.nunito(fontSize: 22, fontWeight: FontWeight.w700),
    titleMedium: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w500),
    bodyLarge: GoogleFonts.nunito(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.nunito(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    labelLarge: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w600),
    labelSmall: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600),
  );

  static ThemeData get lightTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2C5E7A),
      primary: const Color(0xFF2C5E7A),
      secondary: const Color(0xFFE28743),
      error: const Color(0xFFD32F2F),
      surface: const Color(0xFFF8F9FA),
      onSurface: const Color(0xFF212121),
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      textTheme: _textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      inputDecorationTheme: _inputDecorationTheme(colorScheme),
    );
  }

  static ThemeData get darkTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2C5E7A),
      primary: const Color(0xFF5AA5C9),
      secondary: const Color(0xFFE28743),
      error: const Color(0xFFEF9A9A),
      surface: const Color(0xFF121212),
      onSurface: const Color(0xFFE0E0E0),
      brightness: Brightness.dark,
    );

    return ThemeData(
      colorScheme: colorScheme,
      textTheme: _textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade800),
        ),
        color: const Color(0xFF1E1E1E),
      ),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      inputDecorationTheme: _inputDecorationTheme(colorScheme),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme colorScheme) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: _textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimary,
        ),
        elevation: 0,
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(ColorScheme colorScheme) {
    return InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.brightness == Brightness.light
          ? Colors.grey.shade50
          : Colors.grey.shade900,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      labelStyle: _textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
    );
  }
}

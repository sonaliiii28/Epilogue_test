import 'package:flutter/material.dart';

/// Shared gradient & color constants used across all screens.
class AppStyles {
  AppStyles._();

  /// The unified background gradient: deep purple at top → soft lilac at bottom.
  static const backgroundGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF74659A), // deep purple
        Color(0xFFDFDBE5), // soft lilac
      ],
    ),
  );

  /// Primary accent purple.
  static const Color primary = Color(0xFF6B5B95);

  static const Color deepPurple = Color(0xFF2E2540);
  static const Color purple = Color(0xFF7A64A4);
  static const Color mutedPurple = Color(0xFF6C648B);
  static const Color lightPurple = Color(0xFFB0A8C8);
  static const Color borderColor = Color(0xFFD4CDDF);
}

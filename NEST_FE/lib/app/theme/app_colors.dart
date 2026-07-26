import 'package:flutter/material.dart';

/// Exact palette from the two approved brand mockups - dark mode uses the
/// "Option 2" navy/teal/owl treatment, light mode uses "Option 3"'s
/// white/purple/pink treatment. These are deliberately different accent
/// families per theme (not one hue lightened/darkened) - that's the brand,
/// not a bug.
class AppColors {
  AppColors._();

  // ---- Dark (Option 2) ----
  static const darkBg = Color(0xFF0B1212);
  static const darkSurface = Color(0xFF0F1F1D);
  static const darkTeal = Color(0xFF14E3C2);
  static const darkAmber = Color(0xFFFFB020);
  static const darkInk = Color(0xFFFFFFFF);

  // ---- Light (Option 3) ----
  static const lightBg = Color(0xFFF7F8FC);
  static const lightPurple = Color(0xFF6C3BFF);
  static const lightPink = Color(0xFFFF4D9D);
  static const lightAmber = Color(0xFFFFB020);
  static const lightCyan = Color(0xFF00D1FF);
  static const lightInk = Color(0xFF111827);

  // ---- Semantic (same meaning in both themes, tuned per-theme in app_theme.dart) ----
  static const success = Color(0xFF1E8E5A);
  static const warning = Color(0xFFB8860B);
  static const danger = Color(0xFFD64545);
}

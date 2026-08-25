import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_tokens.dart';

/// Two fully-specified Material 3 themes built from [AppColors]. Every screen
/// should read colors through `Theme.of(context).colorScheme` (or the
/// extensions below) rather than referencing [AppColors] directly, so light/
/// dark switching is automatic everywhere.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.darkTeal,
            onPrimary: AppColors.darkBg,
            secondary: AppColors.darkAmber,
            onSecondary: AppColors.darkBg,
            tertiary: AppColors.darkAmber,
            onTertiary: AppColors.darkBg,
            surface: AppColors.darkSurface,
            onSurface: AppColors.darkInk,
            error: AppColors.danger,
            onError: Colors.white,
          )
        : const ColorScheme.light(
            primary: AppColors.lightPurple,
            onPrimary: Colors.white,
            secondary: AppColors.lightPink,
            onSecondary: Colors.white,
            tertiary: AppColors.lightCyan,
            onTertiary: AppColors.lightInk,
            surface: Colors.white,
            onSurface: AppColors.lightInk,
            error: AppColors.danger,
            onError: Colors.white,
          );

    final scaffoldBg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.darkSurface : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      fontFamily: 'Roboto',
      textTheme: _textTheme(colorScheme.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.65)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        side: BorderSide(color: borderColor),
        labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: borderColor, thickness: 1, space: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withValues(alpha: 0.45),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? Colors.white : AppColors.lightInk,
        contentTextStyle: TextStyle(color: isDark ? AppColors.darkBg : Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      // The refreshed design language (see app_tokens.dart), attached as a ThemeExtension so
      // migrated widgets read `context.palette.*` and get the right brightness automatically.
      //
      // Purely additive right now: nothing below reads from it, so every un-migrated screen keeps
      // rendering exactly as before. Modules opt in one at a time (Fees -> Batches -> Dashboard),
      // which is what keeps the app from sitting in a half-restyled state where each individual
      // screen looks broken rather than merely old.
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AppPalette.dark : AppPalette.light,
      ],
    );
  }

  static TextTheme _textTheme(Color ink) {
    return TextTheme(
      displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.3),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
      titleMedium: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: ink),
      bodyLarge: TextStyle(fontSize: 15, color: ink),
      bodyMedium: TextStyle(fontSize: 13.5, color: ink.withValues(alpha: 0.75)),
      bodySmall: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.6)),
      labelLarge: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink),
    );
  }
}

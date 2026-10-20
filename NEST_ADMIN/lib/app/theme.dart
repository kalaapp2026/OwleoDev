import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Owleo HQ design tokens, copied one-to-one from the CSS custom properties in the
/// "Owleo HQ Console" prototype (`--bg`, `--surface`, ...). Screens read colours from here and
/// never write a hex literal, so a palette change is one edit.
abstract final class Hq {
  // Surfaces, darkest to lightest.
  static const bg = Color(0xFF0A0F1C);
  static const surface = Color(0xFF111827);
  static const raised = Color(0xFF161F30);
  static const high = Color(0xFF1C2740);
  static const border = Color(0xFF232F47);
  static const soft = Color(0xFF1B2438);

  // Text.
  static const text = Color(0xFFEDF1F9);
  static const muted = Color(0xFF8A93AC);
  static const faint = Color(0xFF5B6580);

  // Accents. Each one has a soft 12-14% wash used for tiles, tags and deltas.
  static const primary = Color(0xFF2FE0C6);
  static const gold = Color(0xFFF0B429);
  static const red = Color(0xFFE5545A);
  static const green = Color(0xFF2FBD73);
  static const blue = Color(0xFF3FA9F5);
  static const violet = Color(0xFFA78BFA);
  static const coral = Color(0xFFFF8A5B);
  static const magenta = Color(0xFFF0629B);

  /// Text colour on a solid primary button (`#04231D` in the prototype).
  static const onPrimary = Color(0xFF04231D);
  static const ink = Color(0xFF0A0F1C);

  static const radiusCard = 18.0;
  static const radiusBtn = 12.0;

  static Color tint(Color c, [double a = .14]) => c.withValues(alpha: a);
}

/// The named tones the prototype's `tone('x')` helper accepts. Using an enum instead of strings
/// means a typo is a compile error, not a silently grey tag.
enum Tone {
  primary(Hq.primary),
  gold(Hq.gold),
  red(Hq.red),
  green(Hq.green),
  blue(Hq.blue),
  violet(Hq.violet),
  coral(Hq.coral),
  magenta(Hq.magenta),
  mute(Hq.muted);

  const Tone(this.color);
  final Color color;

  /// The soft wash behind a tile or tag. `mute` washes to the raised-high surface, like the CSS.
  Color get soft => this == Tone.mute ? Hq.high : color.withValues(alpha: this == Tone.primary ? .12 : .14);

  static Tone byName(String? name) => Tone.values.firstWhere((t) => t.name == name, orElse: () => Tone.mute);
}

/// Text styles at the prototype's exact sizes. Inter at tabular figures, because every number on
/// this console is meant to be compared down a column.
abstract final class HqText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _inter(double size, FontWeight w, Color c, {double? height, double? spacing}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: w,
        color: c,
        height: height,
        letterSpacing: spacing,
        fontFeatures: _tabular,
      );

  static TextStyle h1 = _inter(22, FontWeight.w800, Hq.text, spacing: -.4);
  static TextStyle h2 = _inter(20, FontWeight.w800, Hq.text, spacing: -.3);
  static TextStyle h3 = _inter(14.5, FontWeight.w800, Hq.text);
  static TextStyle title = _inter(17, FontWeight.w800, Hq.text);
  static TextStyle body = _inter(13.5, FontWeight.w500, Hq.text, height: 1.45);
  static TextStyle bodyStrong = _inter(13, FontWeight.w700, Hq.text);
  static TextStyle row = _inter(13, FontWeight.w700, Hq.text);
  static TextStyle small = _inter(11.5, FontWeight.w500, Hq.muted);
  static TextStyle sub = _inter(11.5, FontWeight.w500, Hq.faint);
  static TextStyle muted = _inter(12.5, FontWeight.w500, Hq.muted);
  static TextStyle label = _inter(12, FontWeight.w700, Hq.muted);
  static TextStyle kpiLabel = _inter(12, FontWeight.w600, Hq.muted);
  static TextStyle kpiValue = _inter(27, FontWeight.w800, Hq.text, height: 1.05, spacing: -.8);
  static TextStyle button = _inter(13, FontWeight.w700, Hq.text);
  static TextStyle th = _inter(10.5, FontWeight.w800, Hq.faint, spacing: .5);
  static TextStyle tag(Color c) => _inter(10.5, FontWeight.w800, c, spacing: .35);
  static TextStyle section = _inter(10.5, FontWeight.w800, Hq.faint, spacing: .5);
}

ThemeData hqTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Hq.bg,
    canvasColor: Hq.bg,
    colorScheme: const ColorScheme.dark(
      primary: Hq.primary,
      onPrimary: Hq.onPrimary,
      secondary: Hq.gold,
      surface: Hq.surface,
      onSurface: Hq.text,
      error: Hq.red,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: Hq.text, displayColor: Hq.text),
    dividerColor: Hq.soft,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Hq.high),
      radius: const Radius.circular(8),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Hq.primary, selectionColor: Color(0x442FE0C6)),
  );
}

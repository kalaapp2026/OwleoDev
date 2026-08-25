import 'package:flutter/material.dart';

/// The type scale from the Fees prototype.
///
/// It is denser than Material's default and uses half-point sizes (11.5, 12.5, 13.5) and unusual
/// weights (650) throughout. That isn't sloppiness in the original - the cards pack a lot of
/// information into a phone width, and rounding everything to Material's scale visibly loosens
/// the layout and costs a row of content per screen. So the odd values are preserved exactly.
///
/// FONT NOTE: the prototype specifies Inter. Nothing is bundled here yet, so these render in the
/// platform default (Roboto on Android, SF on iOS, and whatever the browser picks on web). Inter
/// is a closer match to the intended look, but bundling it adds weight and - more importantly -
/// a Latin-only Inter would break the 11 non-Latin locales we just shipped, since it has no
/// Devanagari/Tamil/Arabic coverage. Worth deciding deliberately rather than dropping in.
abstract final class AppType {
  // --- Weights used by the design ---
  static const FontWeight regular = FontWeight.w500;
  static const FontWeight medium = FontWeight.w600;

  /// The prototype uses 650 here (list-row names, ledger amounts) to sit just under the 700 of
  /// headings. Flutter's [FontWeight] only exposes hundreds, so this rounds DOWN to 600 - keeping
  /// it below 700 preserves the intended hierarchy, where rounding up would flatten names and
  /// headings into the same weight. An exact 650 is only reachable with a variable font via
  /// `FontVariation`, which is worth revisiting if Inter ever gets bundled.
  static const FontWeight semi = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight heavy = FontWeight.w800;

  // --- Sizes ---

  /// Category tag inside a statement row.
  static const double micro = 9.5;

  /// Stat-box labels, footnotes under a figure.
  static const double tiny = 10.5;

  /// Uppercase section labels, breakdown hints.
  static const double xs = 11;

  /// Captions, secondary row text, filter summaries.
  static const double sm = 11.5;

  /// Compact chips, dense secondary text.
  static const double smd = 12;

  /// Body small - subtitles, sheet hints.
  static const double base = 12.5;

  /// Body - section headings inside cards, buttons in dense rows.
  static const double md = 13;

  /// Body emphasis - dialog body, primary row values.
  static const double lg = 13.5;

  /// List item text.
  static const double xl = 14;

  /// Dropdown values, list-row names, primary button labels.
  static const double xxl = 14.5;

  /// Sheet options, text inputs.
  static const double x3l = 15;

  /// Category card titles, stat-box values.
  static const double x4l = 15.5;

  /// Screen titles, profile fee figures.
  static const double title = 17;

  /// The single largest figure on a card (revenue count).
  static const double display = 18;

  // --- Letter spacing ---

  /// Screen titles pull in slightly - at 17px the default tracking reads loose.
  static const double titleTracking = -0.2;

  /// Uppercase labels open up, or the caps run together.
  static const double capsTracking = 0.6;
  static const double capsTrackingTight = 0.5;

  /// Builds the Material [TextTheme] the refreshed design maps onto. Only the slots this design
  /// actually uses are overridden; the rest inherit so un-migrated screens are unaffected.
  static TextTheme textTheme(Color onSurface) {
    TextStyle s(double size, FontWeight weight, {double? tracking, Color? color}) => TextStyle(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: tracking,
          color: color ?? onSurface,
          height: 1.25,
        );

    return TextTheme(
      // Screen and card titles.
      titleLarge: s(title, bold, tracking: titleTracking),
      titleMedium: s(x4l, bold),
      titleSmall: s(md, bold),

      // Figures - the numbers on stat boxes and revenue cards.
      headlineSmall: s(display, heavy),
      headlineMedium: s(x4l, heavy),

      // Body.
      bodyLarge: s(xl, regular),
      bodyMedium: s(lg, regular),
      bodySmall: s(base, regular),

      // Labels - buttons and chips.
      labelLarge: s(xxl, bold),
      labelMedium: s(md, bold),
      labelSmall: s(sm, medium),
    );
  }

  /// Uppercase section label ("SELECT FEE CATEGORY", "TRANSACTION LEDGER"). Used often enough to
  /// be worth a named helper rather than re-specifying caps + tracking + muted at each call site.
  static TextStyle sectionLabel(Color color) => TextStyle(
        fontSize: xs,
        fontWeight: bold,
        letterSpacing: capsTracking,
        color: color,
      );
}

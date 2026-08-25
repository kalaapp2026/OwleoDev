import 'package:flutter/material.dart';

/// The design-token layer for the refreshed Owleo visual language, ported from the Fees
/// prototype and intended to roll out across every module (Fees -> Batches -> Dashboard -> rest).
///
/// Deliberately ADDITIVE. The existing [AppColors] / [AppTheme] stay untouched so screens that
/// haven't been migrated yet keep rendering correctly - a half-migrated app that looks consistent
/// per-screen is far better than one where every screen is half-restyled.
///
/// Everything is exposed through [AppPalette], a [ThemeExtension], so widgets read
/// `context.palette.notPaid` and automatically get the right value for the active brightness -
/// rather than referencing raw constants and silently breaking when the theme flips.

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.border,
    required this.borderSoft,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.primary,
    required this.primaryDim,
    required this.primarySoft,
    required this.onPrimary,
    required this.revenue,
    required this.revenueSoft,
    required this.gold,
    required this.goldDim,
    required this.goldLight,
    required this.goldSoft,
    required this.onGold,
    required this.notPaid,
    required this.notPaidSoft,
    required this.paidManual,
    required this.paidManualSoft,
    required this.gateway,
    required this.gatewaySoft,
    required this.partial,
    required this.partialSoft,
    required this.due,
    required this.dueSoft,
  });

  /// Page background - sits behind [surface].
  final Color bg;

  /// Sheets, dialogs, dropdown panels.
  final Color surface;

  /// Cards and list rows - the most common container in this design.
  final Color surfaceRaised;

  /// Inset wells: progress-bar troughs, avatar chips, inline edit fields.
  final Color surfaceHigh;

  final Color border;

  /// Hairline divider between rows inside a card, where [border] would read too heavily.
  final Color borderSoft;

  final Color text;
  final Color textMuted;
  final Color textFaint;

  /// Teal. Primary action, selection, focus.
  final Color primary;
  final Color primaryDim;

  /// ~12% primary. Selected-chip and selected-row fills.
  final Color primarySoft;

  /// Text/icons ON a filled primary surface. Very dark green, not white - white on this teal
  /// fails contrast at button text sizes.
  final Color onPrimary;

  /// Yellow. Money totals and report actions - deliberately distinct from [primary] so
  /// "this is an amount" never reads as "this is a button".
  final Color revenue;
  final Color revenueSoft;

  /// Amber. Segmented-control selection and inline edit affordances.
  final Color gold;
  final Color goldDim;
  final Color goldLight;
  final Color goldSoft;
  final Color onGold;

  // --- Payment status. Semantic: never reuse these for decoration. ---
  final Color notPaid;
  final Color notPaidSoft;
  final Color paidManual;
  final Color paidManualSoft;
  final Color gateway;
  final Color gatewaySoft;
  final Color partial;
  final Color partialSoft;

  /// Overdue - unpaid AND past its due date. A hotter red-orange than [notPaid] so the two are
  /// distinguishable at a glance in a long list.
  final Color due;
  final Color dueSoft;

  /// Exact values from the prototype. Do not "tidy" these - they were chosen together and the
  /// soft variants are tuned to sit on [surfaceRaised] specifically.
  static const dark = AppPalette(
    bg: Color(0xFF0A0F1C),
    surface: Color(0xFF111827),
    surfaceRaised: Color(0xFF161F30),
    surfaceHigh: Color(0xFF1C2740),
    border: Color(0xFF232F47),
    borderSoft: Color(0xFF1B2438),
    text: Color(0xFFEDF1F9),
    textMuted: Color(0xFF8A93AC),
    textFaint: Color(0xFF5B6580),
    primary: Color(0xFF2FE0C6),
    primaryDim: Color(0xFF1B8F7C),
    primarySoft: Color(0x1F2FE0C6), // 12%
    onPrimary: Color(0xFF04231D),
    revenue: Color(0xFFFFD60A),
    revenueSoft: Color(0x24FFD60A), // 14%
    gold: Color(0xFFF0B429),
    goldDim: Color(0xFFB8791A),
    goldLight: Color(0xFFFFD873),
    goldSoft: Color(0x24F0B429),
    onGold: Color(0xFF1A1200),
    notPaid: Color(0xFFE5545A),
    notPaidSoft: Color(0x24E5545A),
    paidManual: Color(0xFF2FBD73),
    paidManualSoft: Color(0x242FBD73),
    gateway: Color(0xFF3FA9F5),
    gatewaySoft: Color(0x243FA9F5),
    partial: Color(0xFFE8A93A),
    partialSoft: Color(0x24E8A93A),
    due: Color(0xFFFF6B4A),
    dueSoft: Color(0x29FF6B4A), // 16%
  );

  /// DERIVED, not from the prototype - the prototype is dark-only, but the app already ships a
  /// System/Light/Dark setting, so a light counterpart has to exist or that setting becomes a
  /// no-op on every migrated screen.
  ///
  /// The hues are held constant and the lightness re-anchored: accents are darkened enough to
  /// hold contrast on white (the dark palette's teal and yellow are unreadable as text on a light
  /// ground), and the soft fills are lifted slightly since a 12% tint disappears on white.
  /// This one needs a designer's eye before it ships - flagged, not assumed.
  static const light = AppPalette(
    bg: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEDF1F8),
    border: Color(0xFFDCE3EF),
    borderSoft: Color(0xFFE9EDF6),
    text: Color(0xFF0E1626),
    textMuted: Color(0xFF5A6478),
    textFaint: Color(0xFF8892A6),
    primary: Color(0xFF0E9E88),
    primaryDim: Color(0xFF0A7767),
    primarySoft: Color(0x1F0E9E88),
    onPrimary: Color(0xFFFFFFFF),
    revenue: Color(0xFFB07C00),
    revenueSoft: Color(0x24B07C00),
    gold: Color(0xFFB8791A),
    goldDim: Color(0xFF8A5A12),
    goldLight: Color(0xFFE8B45C),
    goldSoft: Color(0x24B8791A),
    onGold: Color(0xFFFFFFFF),
    notPaid: Color(0xFFC5333A),
    notPaidSoft: Color(0x1FC5333A),
    paidManual: Color(0xFF17864B),
    paidManualSoft: Color(0x1F17864B),
    gateway: Color(0xFF1B6FB8),
    gatewaySoft: Color(0x1F1B6FB8),
    partial: Color(0xFFB07A16),
    partialSoft: Color(0x1FB07A16),
    due: Color(0xFFD24520),
    dueSoft: Color(0x1FD24520),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHigh,
    Color? border,
    Color? borderSoft,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? primary,
    Color? primaryDim,
    Color? primarySoft,
    Color? onPrimary,
    Color? revenue,
    Color? revenueSoft,
    Color? gold,
    Color? goldDim,
    Color? goldLight,
    Color? goldSoft,
    Color? onGold,
    Color? notPaid,
    Color? notPaidSoft,
    Color? paidManual,
    Color? paidManualSoft,
    Color? gateway,
    Color? gatewaySoft,
    Color? partial,
    Color? partialSoft,
    Color? due,
    Color? dueSoft,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      primary: primary ?? this.primary,
      primaryDim: primaryDim ?? this.primaryDim,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimary: onPrimary ?? this.onPrimary,
      revenue: revenue ?? this.revenue,
      revenueSoft: revenueSoft ?? this.revenueSoft,
      gold: gold ?? this.gold,
      goldDim: goldDim ?? this.goldDim,
      goldLight: goldLight ?? this.goldLight,
      goldSoft: goldSoft ?? this.goldSoft,
      onGold: onGold ?? this.onGold,
      notPaid: notPaid ?? this.notPaid,
      notPaidSoft: notPaidSoft ?? this.notPaidSoft,
      paidManual: paidManual ?? this.paidManual,
      paidManualSoft: paidManualSoft ?? this.paidManualSoft,
      gateway: gateway ?? this.gateway,
      gatewaySoft: gatewaySoft ?? this.gatewaySoft,
      partial: partial ?? this.partial,
      partialSoft: partialSoft ?? this.partialSoft,
      due: due ?? this.due,
      dueSoft: dueSoft ?? this.dueSoft,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      border: c(border, other.border),
      borderSoft: c(borderSoft, other.borderSoft),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      textFaint: c(textFaint, other.textFaint),
      primary: c(primary, other.primary),
      primaryDim: c(primaryDim, other.primaryDim),
      primarySoft: c(primarySoft, other.primarySoft),
      onPrimary: c(onPrimary, other.onPrimary),
      revenue: c(revenue, other.revenue),
      revenueSoft: c(revenueSoft, other.revenueSoft),
      gold: c(gold, other.gold),
      goldDim: c(goldDim, other.goldDim),
      goldLight: c(goldLight, other.goldLight),
      goldSoft: c(goldSoft, other.goldSoft),
      onGold: c(onGold, other.onGold),
      notPaid: c(notPaid, other.notPaid),
      notPaidSoft: c(notPaidSoft, other.notPaidSoft),
      paidManual: c(paidManual, other.paidManual),
      paidManualSoft: c(paidManualSoft, other.paidManualSoft),
      gateway: c(gateway, other.gateway),
      gatewaySoft: c(gatewaySoft, other.gatewaySoft),
      partial: c(partial, other.partial),
      partialSoft: c(partialSoft, other.partialSoft),
      due: c(due, other.due),
      dueSoft: c(dueSoft, other.dueSoft),
    );
  }
}

/// `context.palette.notPaid` - shorter than the ThemeExtension lookup at every call site, and
/// falls back to the dark palette rather than throwing if a widget is built outside the themed
/// tree (which happens in tests and in isolated widget previews).
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

// ---------------------------------------------------------------------------
// Spacing
// ---------------------------------------------------------------------------

/// The prototype's spacing values, deduplicated. It uses a fairly fine-grained scale (6/7/8/10)
/// because the cards are information-dense; snapping everything to a 4pt grid would have made
/// list rows noticeably taller and cost a row of visible content on a phone.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 14;
  static const double xxl = 16;
  static const double x3l = 18;
  static const double x4l = 20;
  static const double x5l = 24;
  static const double x6l = 28;

  /// Standard page gutter.
  static const double page = 20;

  /// Bottom padding on scrollable lists so the last row clears a floating action / toast.
  static const double listBottom = 90;
}

// ---------------------------------------------------------------------------
// Radii
// ---------------------------------------------------------------------------

abstract final class AppRadii {
  /// Inline edit fields inside a list row.
  static const double xs = 6;

  /// Status badges, small icon buttons.
  static const double sm = 8;

  /// Segmented-control inner selection.
  static const double smd = 9;

  /// Buttons, the paid toggle.
  static const double md = 10;

  /// Icon buttons, input wrappers, filter chips.
  static const double lg = 12;

  /// Dropdowns, inputs, primary buttons.
  static const double xl = 14;

  /// Cards, list rows.
  static const double xxl = 16;

  /// Category cards.
  static const double x3l = 18;

  /// Dialogs.
  static const double x4l = 20;

  /// Bottom-sheet top corners.
  static const double sheet = 24;

  /// Fully rounded - pills and segmented controls.
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static const sheetTop = BorderRadius.only(
    topLeft: Radius.circular(sheet),
    topRight: Radius.circular(sheet),
  );
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Durations and curves lifted from the prototype's CSS, kept as named tokens so the feel stays
/// identical across every widget that animates. The prototype's house curve is
/// `cubic-bezier(0.2, 0.8, 0.3, 1)` - a fast-out, settle-in ease used for anything that enters.
abstract final class AppMotion {
  /// The house curve. Enters fast, settles without bouncing.
  static const Curve enter = Cubic(0.2, 0.8, 0.3, 1.0);

  /// Press feedback and the first half of the flip toggle - accelerating, because the element is
  /// leaving rather than arriving.
  static const Curve exit = Curves.easeIn;

  static const Duration dropdown = Duration(milliseconds: 180);
  static const Duration dialog = Duration(milliseconds: 220);
  static const Duration toast = Duration(milliseconds: 250);
  static const Duration screen = Duration(milliseconds: 260);
  static const Duration sheet = Duration(milliseconds: 280);
  static const Duration row = Duration(milliseconds: 300);

  /// Press-scale feedback (0.96).
  static const Duration press = Duration(milliseconds: 120);

  /// One half of the flip toggle - it closes to edge-on, swaps content, then opens.
  /// The full gesture reads as ~340ms; each half is this.
  static const Duration flipHalf = Duration(milliseconds: 170);

  /// Colour cross-fade under the flip, deliberately slower than the rotation so the colour
  /// change reads as continuous rather than snapping at the halfway point.
  static const Duration flipColor = Duration(milliseconds: 340);

  static const Duration progress = Duration(milliseconds: 400);
  static const Duration donut = Duration(milliseconds: 500);
  static const Duration chevron = Duration(milliseconds: 200);

  /// The selector block collapsing as the student list scrolls.
  static const Duration collapse = Duration(milliseconds: 280);
  static const Duration fade = Duration(milliseconds: 200);
  static const Duration focus = Duration(milliseconds: 180);

  /// Press-scale factor applied to buttons that aren't opted out.
  static const double pressScale = 0.96;
}

// ---------------------------------------------------------------------------
// Elevation
// ---------------------------------------------------------------------------

/// The prototype leans on large, very soft, near-black shadows rather than Material elevation
/// tints - on a near-black background a tint does nothing, so depth has to come from the shadow.
abstract final class AppShadows {
  static const dropdown = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 36, offset: Offset(0, 16)),
  ];
  static const dialog = [
    BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20)),
  ];
  static const calendar = [
    BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 20)),
  ];
  static const toast = [
    BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10)),
  ];

  /// Focus ring: a 1px primary outline plus a soft glow. Reproduces the prototype's
  /// `0 0 0 1px primary, 0 0 9px rgba(primary, 0.55)`.
  static List<BoxShadow> focusGlow(Color primary) => [
        BoxShadow(color: primary.withValues(alpha: 0.55), blurRadius: 9),
      ];
}

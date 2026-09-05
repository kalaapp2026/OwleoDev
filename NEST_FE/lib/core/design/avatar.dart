import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// A student's initials in a rounded square, standing in for a photo.
///
/// Deliberately neutral rather than colour-coded by name. On a list where colour already carries
/// payment status, tinting the avatar too would add a second colour language competing with the
/// one that matters.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  /// First letter of the first two words. A single-word name gives one letter rather than padding
  /// it out with something invented.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts[0][0];
    final second = parts.length > 1 ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadii.all(size * 0.3),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: AppType.bold,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

/// A circular initials avatar tinted from a stable per-person colour.
///
/// The counterpart to [InitialsAvatar]: used on Batches, Users and Schedule, where nothing else
/// in the row encodes meaning through colour, so tinting per person helps the eye track someone
/// down a long list. Not used on Fees, where colour already means payment status.
///
/// The tint is derived from [seed] rather than the name, so two people called "Aarav S." stay
/// visually distinct and one person keeps the same colour even after a rename.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 32,
  });

  final String name;
  final String seed;
  final double size;

  /// The six category-adjacent accents, chosen because they are already tuned to this palette
  /// and to sit on [AppPalette.surfaceRaised].
  static List<Color> _paletteFor(AppPalette p) =>
      [p.primary, p.gold, p.violet, p.coral, p.magenta, p.gateway];

  /// Deterministic so a person's colour never changes between builds or devices. Plain FNV-ish
  /// string hash - the distribution only has to be even across six buckets.
  static Color colorFor(String seed, AppPalette palette) {
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final options = _paletteFor(palette);
    return options[hash % options.length];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = colorFor(seed, palette);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.33)),
      ),
      child: Text(
        InitialsAvatar.initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: AppType.bold,
          color: color,
        ),
      ),
    );
  }
}

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

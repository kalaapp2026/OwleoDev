import 'package:flutter/material.dart';

enum OwleoWordmarkSize { small, large }

/// Brand mark used on the login screen and app bar: the Owleo Nest owl icon plus the
/// "Owleo / NEST" wordmark.
class OwleoWordmark extends StatelessWidget {
  const OwleoWordmark({super.key, this.size = OwleoWordmarkSize.small});

  final OwleoWordmarkSize size;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == OwleoWordmarkSize.large;
    final iconSize = isLarge ? 64.0 : 34.0;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NestOwlIcon(size: iconSize),
        SizedBox(width: isLarge ? 14 : 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Owleo',
              style: TextStyle(
                fontSize: isLarge ? 34 : 19,
                fontWeight: FontWeight.w800,
                height: 1.0,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'NEST',
              style: TextStyle(
                fontSize: isLarge ? 14 : 9,
                fontWeight: FontWeight.w700,
                letterSpacing: isLarge ? 5 : 3,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The Nest owl app icon, rounded to match how it appears as a launcher icon.
class NestOwlIcon extends StatelessWidget {
  const NestOwlIcon({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/brand/owl_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

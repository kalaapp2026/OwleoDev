import 'package:flutter/material.dart';
import 'package:nest_fe/core/network/api_config.dart';

/// A person's photo if they've uploaded one, otherwise the first letter of their name in a
/// coloured circle - the fallback the Attendance module (and anywhere else showing a roster)
/// needs for students who never set a profile picture.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.imageUrl, this.radius = 20});

  final String name;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = ApiConfig.resolveMediaUrl(imageUrl);
    final colorScheme = Theme.of(context).colorScheme;

    if (resolvedUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(resolvedUrl),
        backgroundColor: colorScheme.surfaceContainerHighest,
      );
    }

    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
      ),
    );
  }
}

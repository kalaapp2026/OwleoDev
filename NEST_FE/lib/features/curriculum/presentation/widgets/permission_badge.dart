import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';

/// "Downloadable" / "View only", as the small pill that sits on every material row and in the
/// viewer's header.
class PermissionBadge extends StatelessWidget {
  const PermissionBadge({super.key, required this.permission});

  final StudyMaterialPermission permission;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = permission.color(palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: permission.softColor(palette),
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.33)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(permission.icon, size: 10.5, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            permission.label,
            style: TextStyle(
              fontSize: AppType.tiny,
              fontWeight: AppType.heavy,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

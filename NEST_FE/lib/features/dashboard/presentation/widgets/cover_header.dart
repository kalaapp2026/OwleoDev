import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';

/// The Dashboard's cover header: academy identity and a role-aware greeting.
///
/// Deliberately has no bell and no theme toggle - both already live in [AppShell]'s app bar, and
/// duplicating them here would be a second, inconsistent copy of the same control rather than a
/// missing feature.
class DashboardCoverHeader extends StatelessWidget {
  const DashboardCoverHeader({
    super.key,
    required this.academyName,
    required this.roleLabel,
  });

  final String academyName;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          PersonAvatar(name: academyName, seed: academyName, size: 52),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  academyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppType.heavy,
                    letterSpacing: AppType.titleTracking,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: AppType.base,
                    fontWeight: AppType.medium,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

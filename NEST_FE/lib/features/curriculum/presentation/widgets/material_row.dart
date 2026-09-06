import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
/// One file row. Shared by the library and the playlist screens so a track looks the same
/// wherever it turns up.
class MaterialRow extends StatelessWidget {
  const MaterialRow({
    super.key,
    required this.material,
    required this.onTap,
    this.trailing,
    this.leading,
    this.highlighted = false,
  });

  final StudyMaterial material;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;

  /// Marks the track currently open, so a long playlist says where you are.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = material.fileType.color(palette);

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: highlighted ? accent.withValues(alpha: 0.1) : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(
              color: highlighted
                  ? accent.withValues(alpha: 0.45)
                  : palette.borderSoft),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.md),
            ],
            Container(
              height: 40,
              width: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: material.fileType.softColor(palette),
                borderRadius: AppRadii.all(AppRadii.lg),
              ),
              child: Icon(material.fileType.icon, size: 18, color: accent),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(material.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.xxl,
                          fontWeight: AppType.medium,
                          color: palette.text)),
                  const SizedBox(height: 3),
                  Text(
                    '${material.sizeLabel} · ${formatFeeDate(material.uploadedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: AppType.sm, color: palette.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing ??
                StatusBadge(
                  label: material.permission.label,
                  color: material.permission.color(palette),
                  dense: true,
                ),
          ],
        ),
      ),
    );
  }
}

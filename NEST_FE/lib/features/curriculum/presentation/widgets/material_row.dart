import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/permission_badge.dart';

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
    this.highlightColor,
    this.originLine,
    this.originColor,
  });

  final StudyMaterial material;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;

  /// Marks the track currently open, so a long list says where you are.
  final bool highlighted;

  /// Defaults to the file type's colour.
  final Color? highlightColor;

  /// "Batch A · Guitar Beginner" - where the file came from. Only the cross-batch libraries have
  /// any use for it.
  final String? originLine;
  final Color? originColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = material.fileType.color(palette);
    final highlight = highlightColor ?? accent;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: highlighted ? highlight.withValues(alpha: 0.12) : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: highlighted ? highlight : palette.borderSoft),
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
                          fontSize: AppType.xl,
                          fontWeight: AppType.semi,
                          color: palette.text)),
                  if (originLine != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (originColor != null) ...[
                          Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: originColor, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(originLine!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: AppType.sm,
                                  fontWeight: AppType.semi,
                                  color: originColor ?? palette.textFaint)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '${material.sizeLabel} · ${formatFeeDate(material.uploadedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing ?? PermissionBadge(permission: material.permission),
          ],
        ),
      ),
    );
  }
}

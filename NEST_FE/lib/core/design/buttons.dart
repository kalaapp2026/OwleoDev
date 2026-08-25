import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// Full-width teal CTA. Disabled state is a flat raised surface with faint text rather than a
/// dimmed teal - a translucent primary still reads as "tappable, just loading", which is exactly
/// the wrong signal when the form is genuinely incomplete.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Swaps the content for a spinner while keeping the button's exact size, so the layout below
  /// it doesn't shift for the duration of a request.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null && !busy;

    return Pressable(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xl),
        decoration: BoxDecoration(
          color: enabled ? palette.primary : palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.xl),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: busy
              ? [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: palette.onPrimary),
                  ),
                ]
              : [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: enabled ? palette.onPrimary : palette.textFaint),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.xxl,
                        fontWeight: AppType.bold,
                        color: enabled ? palette.onPrimary : palette.textFaint,
                      ),
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}

/// A filter/segment chip. Selected state is a primary-tinted fill with a primary border, which
/// is how the prototype distinguishes "this filter is on" from a plain tappable chip.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Overrides the selection colour - the report/download chip uses the revenue yellow so it
  /// reads as an action rather than another filter.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = accent ?? palette.primary;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? tint.withValues(alpha: 0.12) : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: selected ? tint : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? tint : palette.textMuted),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.base,
                fontWeight: AppType.medium,
                color: selected ? tint : palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

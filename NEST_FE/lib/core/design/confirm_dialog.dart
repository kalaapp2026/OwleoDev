import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// The design's confirmation dialog: No / destructive-Yes.
///
/// Returns false on barrier dismiss rather than null, so callers can `if (await ...)` without
/// having to remember that "dismissed" and "declined" mean the same thing here. Every use of this
/// guards a destructive or surprising action, and dismissing one must never be read as consent.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'No',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.palette;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.x5l),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(AppSpacing.x4l),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadii.all(AppRadii.x4l),
            border: Border.all(color: palette.border),
            boxShadow: AppShadows.dialog,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppType.x3l,
                  fontWeight: AppType.heavy,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: TextStyle(
                  fontSize: AppType.md,
                  color: palette.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.x3l),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: cancelLabel,
                      onTap: () => Navigator.of(dialogContext).pop(false),
                      background: Colors.transparent,
                      foreground: palette.textMuted,
                      border: palette.border,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _DialogButton(
                      label: confirmLabel,
                      onTap: () => Navigator.of(dialogContext).pop(true),
                      background: palette.notPaid,
                      foreground: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.border,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.lg,
            fontWeight: AppType.bold,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

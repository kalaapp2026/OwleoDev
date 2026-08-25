import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// A status pill: coloured text on a soft tint of the same hue.
///
/// Deliberately knows nothing about payments. It takes a label and a colour, so Batches can use
/// it for active/archived and Billing for paid/overdue without either module having to reach into
/// the other's vocabulary. Domain types map themselves onto it (see PaymentStatus in the fees
/// module) rather than this widget growing a switch over every enum in the app.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.softColor,
    this.dense = false,
  });

  final String label;
  final Color color;

  /// The pill fill. Defaults to a tint of [color] - passing it explicitly is only worth doing
  /// when the design specifies an exact alpha, as the payment statuses do.
  final Color? softColor;

  /// Smaller variant used inside statement rows, where the badge sits beside a label rather than
  /// standing alone at the end of a row.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : 9,
        vertical: dense ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: softColor ?? color.withValues(alpha: 0.14),
        borderRadius: AppRadii.all(dense ? AppRadii.xs : AppRadii.sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: dense ? AppType.micro : AppType.xs,
          fontWeight: AppType.bold,
          color: color,
          letterSpacing: dense ? 0.3 : null,
        ),
      ),
    );
  }
}

/// A small labelled figure - "Agreed fee / ₹1,000". Three of these sit in a row on the profile.
class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value, this.accent});

  final String label;
  final String value;

  /// Tints the figure only, never the label - so a red balance still reads as "Balance", not as
  /// an error state for the whole box.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.tiny, color: palette.textMuted),
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Amounts vary wildly in width (₹500 vs ₹1,23,450) and these boxes are a third of the
            // screen each, so the figure scales down rather than wrapping or clipping.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppType.x4l,
                  fontWeight: AppType.heavy,
                  color: accent ?? palette.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

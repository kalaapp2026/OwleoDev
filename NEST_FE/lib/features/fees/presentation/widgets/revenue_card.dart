import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/fees/data/fee_summary.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';

/// One category's headline on the fees landing.
///
/// Collapsed it answers "how much of what we expected have we got"; expanded it says where that
/// money physically is - cash box, gateway, or still outstanding.
class RevenueCard extends StatelessWidget {
  const RevenueCard({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.summary,
    required this.expanded,
    required this.onToggle,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final CategorySummary summary;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Expanded(
      child: Pressable(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: AppMotion.fade,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.x3l),
            border: Border.all(color: expanded ? palette.revenue : palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: iconColor),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.xs,
                        fontWeight: AppType.bold,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppMotion.chevron,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 14, color: palette.textFaint),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(
                  text: '${summary.paidCount}',
                  style: TextStyle(
                    fontSize: AppType.x4l,
                    fontWeight: AppType.heavy,
                    color: palette.text,
                  ),
                  children: [
                    TextSpan(
                      text: ' / ${summary.totalCount} paid',
                      style: TextStyle(
                        fontSize: AppType.smd,
                        fontWeight: AppType.bold,
                        color: palette.textFaint,
                      ),
                    ),
                  ],
                )),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppProgressBar(
                paid: summary.paidCount,
                // A category nobody is enrolled in would divide by zero; the bar guards it, and 1
                // keeps an empty card showing an empty bar rather than a full one.
                total: summary.totalCount == 0 ? 1 : summary.totalCount,
                compact: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: palette.borderSoft),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  DonutChart(percent: summary.percent, color: palette.revenue),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            money(summary.collected),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: AppType.x3l,
                              fontWeight: AppType.heavy,
                              color: palette.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'of ${money(summary.expected)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // AnimatedSize rather than a conditional child, so opening the card grows it rather
              // than snapping - the two cards sit side by side and a snap moves its neighbour too.
              AnimatedSize(
                duration: AppMotion.collapse,
                curve: AppMotion.enter,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          Divider(height: 1, color: palette.borderSoft),
                          const SizedBox(height: AppSpacing.sm),
                          _SplitRow(
                            label: 'Cash / UPI',
                            value: money(summary.manualAmount),
                            dotColor: palette.paidManual,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _SplitRow(
                            label: 'Payment Gateway',
                            value: money(summary.gatewayAmount),
                            dotColor: palette.gateway,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Divider(height: 1, color: palette.borderSoft),
                          const SizedBox(height: AppSpacing.xs),
                          _SplitRow(
                            label: 'Pending',
                            value: money(summary.pending),
                            dotColor: palette.notPaid,
                            valueColor: palette.notPaid,
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.label,
    required this.value,
    required this.dotColor,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color dotColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: AppType.smd,
            fontWeight: AppType.bold,
            color: valueColor ?? palette.text,
          ),
        ),
      ],
    );
  }
}

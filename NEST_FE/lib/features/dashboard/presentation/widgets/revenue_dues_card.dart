import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/fees/data/fee_summary.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

final _dashboardSummaryProvider = FutureProvider.autoDispose.family<FeeSummary, String>((ref, period) {
  return ref.watch(feesApiProvider).summary(period: period);
});

/// Regular fees only, for the month in view - the same category the Fees landing calls "Regular",
/// scoped down to a single at-a-glance figure. Callers must gate this card on the FEES_ENTRY
/// feature (or admin) themselves; it does no gating of its own.
class RevenueDuesCard extends ConsumerStatefulWidget {
  const RevenueDuesCard({super.key});

  @override
  ConsumerState<RevenueDuesCard> createState() => _RevenueDuesCardState();
}

class _RevenueDuesCardState extends ConsumerState<RevenueDuesCard> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final period = periodOf(_month);
    final summaryAsync = ref.watch(_dashboardSummaryProvider(period));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Revenue & dues',
                  style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text),
                ),
              ),
              AppIconButton(
                icon: Icons.chevron_left,
                size: 28,
                iconSize: 15,
                onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              SizedBox(
                width: 74,
                child: Text(
                  '${monthsShort[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.text),
                ),
              ),
              AppIconButton(
                icon: Icons.chevron_right,
                size: 28,
                iconSize: 15,
                onTap: () {
                  final now = DateTime.now();
                  final next = DateTime(_month.year, _month.month + 1);
                  if (!next.isAfter(DateTime(now.year, now.month))) setState(() => _month = next);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AsyncValueView<FeeSummary>(
            value: summaryAsync,
            onRetry: () => ref.invalidate(_dashboardSummaryProvider(period)),
            data: (context, summary) {
              final regular = summary.regular;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      DonutChart(percent: regular.percent, color: palette.revenue, size: 60),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                money(regular.collected),
                                style: TextStyle(fontSize: AppType.x4l, fontWeight: AppType.heavy, color: palette.text),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'of ${money(regular.expected)} expected',
                              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: palette.notPaidSoft,
                      borderRadius: AppRadii.all(AppRadii.lg),
                      border: Border.all(color: palette.notPaid.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 14, color: palette.notPaid),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Balance due',
                            style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.notPaid),
                          ),
                        ),
                        Text(
                          money(regular.pending),
                          style: TextStyle(fontSize: AppType.md, fontWeight: AppType.heavy, color: palette.notPaid),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Pressable(
                    onTap: () => context.findAncestorStateOfType<AppShellState>()?.goToErpTab(3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: palette.primarySoft,
                        borderRadius: AppRadii.all(AppRadii.lg),
                        border: Border.all(color: palette.primary.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Open Fees Collection',
                            style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.primary),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Icon(Icons.arrow_outward, size: 14, color: palette.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

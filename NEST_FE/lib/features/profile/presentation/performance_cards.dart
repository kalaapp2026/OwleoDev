import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart';

/// The whole fee history, all categories - the Fees summary reads the same statement the full
/// fee profile does, so the two cannot disagree about what is owed.
final _feeStatementProvider = FutureProvider.autoDispose.family<StudentStatement, String>(
    (ref, membershipId) => ref.watch(feesApiProvider).statement(membershipId: membershipId));

/// "PERFORMANCE AT OWLEO ACADEMY" - the label above the two summary cards.
class PerformanceLabel extends StatelessWidget {
  const PerformanceLabel(this.academyName, {super.key});
  final String? academyName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        academyName == null ? 'PERFORMANCE' : 'PERFORMANCE AT ${academyName!.toUpperCase()}',
        style: TextStyle(
            fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textFaint, letterSpacing: 0.6),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.color, required this.soft, required this.title, required this.subtitle});
  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: soft, borderRadius: AppRadii.all(AppRadii.lg)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.heavy, color: palette.text)),
              Text(subtitle, style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon + big figure + caps label, on a tinted, outlined tile.
class _FigurePill extends StatelessWidget {
  const _FigurePill({required this.icon, required this.color, required this.soft, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final Color soft;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: color.withValues(alpha: 0.27)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: value, style: TextStyle(fontSize: AppType.display, fontWeight: AppType.heavy, color: color)),
                TextSpan(text: '  ${label.toUpperCase()}', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: color)),
              ])),
            ),
          ),
        ],
      ),
    );
  }
}

String _title(StatementRow r) {
  if (r.category != FeeCategory.regular) return r.label;
  // A regular row's label is its period, "2026-08".
  final parts = r.label.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return r.label;
  return 'Monthly Fee — ${monthsShort[month - 1]}';
}

String _badge(PaymentStatus s) => switch (s) {
      PaymentStatus.notPaid => 'Not Paid',
      PaymentStatus.due => 'Due',
      PaymentStatus.partial => 'Partial',
      PaymentStatus.paidManual => 'Paid',
      PaymentStatus.paidGateway => 'Paid · Gateway',
      PaymentStatus.closed => 'Closed',
    };

class FeesSummaryCard extends ConsumerWidget {
  const FeesSummaryCard({super.key, required this.membershipId, required this.onOpenFull});
  final String membershipId;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(_feeStatementProvider(membershipId));
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.currency_rupee,
            color: palette.gold,
            soft: palette.goldSoft,
            title: 'Fees',
            subtitle: 'Regular & other fees at this academy',
          ),
          const SizedBox(height: AppSpacing.lg),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator())),
            error: (_, _) => Text('Could not load fees.', style: TextStyle(fontSize: AppType.smd, color: palette.notPaid)),
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _FigurePill(
                          icon: Icons.currency_rupee,
                          color: palette.notPaid,
                          soft: palette.notPaidSoft,
                          value: money(s.outstanding),
                          label: 'Due'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _FigurePill(
                          icon: Icons.check_circle_outline,
                          color: palette.paidManual,
                          soft: palette.paidManualSoft,
                          value: money(s.totalPaid),
                          label: 'Paid'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (s.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text('No fees recorded yet.', style: TextStyle(fontSize: AppType.smd, color: palette.textFaint)),
                  ),
                for (final (i, r) in s.rows.take(3).indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    decoration: BoxDecoration(
                      border: i == 0 ? null : Border(top: BorderSide(color: palette.borderSoft)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_title(r),
                                  style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                              const SizedBox(height: 2),
                              Text(r.paidOn != null ? 'Paid ${formatFeeDate(r.paidOn!)}' : r.context,
                                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                            ],
                          ),
                        ),
                        Text(money(r.fee),
                            style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.textMuted)),
                        const SizedBox(width: AppSpacing.md),
                        StatusBadge(label: _badge(r.status), color: r.status.color(palette), softColor: r.status.softColor(palette)),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Pressable(
                  onTap: onOpenFull,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: AppRadii.all(AppRadii.xl),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Open full fee profile',
                            style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.primary)),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(Icons.chevron_right, size: 16, color: palette.primary),
                      ],
                    ),
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

class AttendanceSummaryCard extends ConsumerWidget {
  const AttendanceSummaryCard({super.key, required this.membershipId, required this.onOpenFull});
  final String membershipId;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(studentAttendanceProvider(membershipId));
    return ProfileCard(
      child: async.when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator())),
        error: (_, _) => Text('Could not load attendance.', style: TextStyle(fontSize: AppType.smd, color: palette.notPaid)),
        data: (all) {
          // Newest first, then the last 20 - a window, not the whole history.
          final recent = ([...all]..sort((a, b) => b.date.compareTo(a.date))).take(20).toList();
          final present = recent.where((r) => r.status == AttendanceStatus.present).length;
          final absent = recent.length - present;
          final percent = recent.isEmpty ? 0.0 : present * 100 / recent.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CardHeader(
                icon: Icons.fact_check_outlined,
                color: palette.gateway,
                soft: palette.gatewaySoft,
                title: 'Classes Attended',
                subtitle: recent.isEmpty ? 'No classes marked yet' : 'Last ${recent.length} classes at this academy',
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    DonutChart(percent: percent, color: palette.paidManual, size: 70, strokeWidth: 8),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: _FigurePill(
                                icon: Icons.check_circle_outline,
                                color: palette.paidManual,
                                soft: palette.paidManualSoft,
                                value: '$present',
                                label: 'Present'),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: _FigurePill(
                                icon: Icons.cancel_outlined,
                                color: palette.notPaid,
                                soft: palette.notPaidSoft,
                                value: '$absent',
                                label: 'Absent'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x3l),
                Text('RECENT CLASSES',
                    style: TextStyle(
                        fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textFaint, letterSpacing: 0.6)),
                const SizedBox(height: AppSpacing.sm),
                for (final (i, r) in recent.take(5).indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    decoration: BoxDecoration(
                      border: i == 0 ? null : Border(top: BorderSide(color: palette.borderSoft)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(formatFeeDate(r.date),
                                  style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                              if (r.batchName != null || r.courseName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text([r.batchName, r.courseName].whereType<String>().join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                                ),
                            ],
                          ),
                        ),
                        StatusBadge(
                            label: r.status.label, color: r.status.color(palette), softColor: r.status.softColor(palette)),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Pressable(
                  onTap: onOpenFull,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: AppRadii.all(AppRadii.xl),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Open full attendance',
                            style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.primary)),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(Icons.chevron_right, size: 16, color: palette.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

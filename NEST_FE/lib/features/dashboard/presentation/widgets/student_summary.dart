import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// A "fee due" tile/card was tried here and pulled out: /students/{id}/statement is gated behind
// the FEES_ENTRY feature (admin/trainer only, see FeesController) so a plain student gets a 403
// even for their own membershipId - there is no backend route today for student self-service fee
// viewing. Revisit when the Fees pass happens; showing a permanently-broken card is worse than
// leaving it out (see this file's dashboard_screen.dart sibling comment on real-data-only cards).

/// Three at-a-glance tiles: this month's attendance, enrolled course count and today's class
/// count. Mirrors [DashboardStatsRow]'s tile layout but colour-coded per figure and wired to a
/// single student's own data instead of academy-wide aggregates.
class StudentQuickStats extends ConsumerWidget {
  const StudentQuickStats({
    super.key,
    required this.membershipId,
    required this.academyId,
    required this.courseCount,
  });

  final String membershipId;
  final String academyId;
  final int courseCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(studentAttendanceProvider(membershipId));
    final today = _dateOnly(DateTime.now());
    final scheduleAsync =
        ref.watch(scheduleFeedProvider((from: today, to: today, courseId: null)));

    final attendanceLabel = attendanceAsync.maybeWhen(
      data: (records) {
        final ratio = AttendanceMonthSummary.of(
          records,
          DateTime.now(),
        ).presentRatio;
        return ratio == null ? '—' : '${(ratio * 100).round()}%';
      },
      orElse: () => '—',
    );
    final todayLabel = scheduleAsync.maybeWhen(
      data: (classes) => '${classes.where((c) => c.status.meets).length}',
      orElse: () => '—',
    );

    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: _StudentStatTile(
            icon: Icons.fact_check_outlined,
            label: 'Attendance',
            value: attendanceLabel,
            color: palette.primary,
            softColor: palette.primarySoft,
            onTap: () =>
                context.findAncestorStateOfType<AppShellState>()?.goToErpTab(1),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StudentStatTile(
            icon: Icons.auto_stories_outlined,
            label: 'My courses',
            value: '$courseCount',
            color: palette.violet,
            softColor: palette.violetSoft,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StudentStatTile(
            icon: Icons.calendar_today_outlined,
            label: 'Today',
            value: todayLabel,
            color: palette.gateway,
            softColor: palette.gatewaySoft,
          ),
        ),
      ],
    );
  }
}

class _StudentStatTile extends StatelessWidget {
  const _StudentStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.softColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color softColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: softColor,
                borderRadius: AppRadii.all(AppRadii.sm),
              ),
              child: Icon(icon, size: 13, color: color),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.x4l,
                fontWeight: AppType.heavy,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.semi,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The detail card below the quick-stat tiles: an attendance ring for the current month.
class StudentAttendanceSummary extends ConsumerWidget {
  const StudentAttendanceSummary({super.key, required this.membershipId});

  final String membershipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final attendanceAsync = ref.watch(studentAttendanceProvider(membershipId));

    return _Card(
      child: AsyncValueView<List<StudentAttendanceRecord>>(
        value: attendanceAsync,
        onRetry: () => ref.invalidate(studentAttendanceProvider(membershipId)),
        data: (context, records) {
          final summary = AttendanceMonthSummary.of(records, DateTime.now());
          final ratio = summary.presentRatio;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This month',
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.bold,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  DonutChart(
                    percent: (ratio ?? 0) * 100,
                    color: palette.primary,
                    size: 52,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      summary.total == 0
                          ? 'No classes marked yet'
                          : '${summary.present}/${summary.total} classes',
                      style: TextStyle(
                        fontSize: AppType.sm,
                        fontWeight: AppType.semi,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

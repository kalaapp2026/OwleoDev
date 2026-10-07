import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart' show FeeCategory;
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// What the student still owes, with the most pressing item to name on the dashboard's Due card.
typedef _FeeDue = ({num amount, String? line, DateTime? due});

final _myFeeDueProvider = FutureProvider.autoDispose<_FeeDue>((ref) async {
  final statement = await ref.watch(feesApiProvider).myStatement();
  final other = await ref.watch(feesApiProvider).myOtherFees();
  final unpaidOther = other.fees.where((f) => !f.status.isSettled).toList()
    ..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
  final unpaidRegular =
      statement.rows.where((r) => r.category == FeeCategory.regular && !r.status.isSettled).toList();
  // A fee with a due date outranks one without; otherwise the course fee is the headline.
  final datedOther = unpaidOther.where((f) => f.dueDate != null).toList();
  String? line;
  DateTime? due;
  if (datedOther.isNotEmpty) {
    line = datedOther.first.name;
    due = datedOther.first.dueDate;
  } else if (unpaidRegular.isNotEmpty) {
    line = '${unpaidRegular.first.context} · ${unpaidRegular.first.label}';
  } else if (unpaidOther.isNotEmpty) {
    line = unpaidOther.first.name;
  }
  return (amount: statement.outstanding + other.outstanding, line: line, due: due);
});

/// Four at-a-glance tiles: this month's attendance, enrolled course count and today's class
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

    final feeDue = ref.watch(_myFeeDueProvider).maybeWhen(data: (d) => money(d.amount), orElse: () => '—');
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
            icon: Icons.account_balance_wallet_outlined,
            label: 'Fee due',
            value: feeDue,
            color: palette.notPaid,
            softColor: palette.notPaidSoft,
            onTap: () => context.findAncestorStateOfType<AppShellState>()?.goToErpTab(3),
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

/// The row under the quick-stat tiles: this month's attendance ring beside the fee Due card.
class StudentAttendanceSummary extends ConsumerWidget {
  const StudentAttendanceSummary({super.key, required this.membershipId});

  final String membershipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _AttendanceRing(membershipId: membershipId)),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: _DueCard()),
        ],
      ),
    );
  }
}

class _AttendanceRing extends ConsumerWidget {
  const _AttendanceRing({required this.membershipId});
  final String membershipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final attendanceAsync = ref.watch(studentAttendanceProvider(membershipId));
    return Pressable(
      onTap: () => context.findAncestorStateOfType<AppShellState>()?.goToErpTab(1),
      borderRadius: AppRadii.all(AppRadii.x3l),
      child: _Card(
        child: AsyncValueView<List<StudentAttendanceRecord>>(
          value: attendanceAsync,
          onRetry: () => ref.invalidate(studentAttendanceProvider(membershipId)),
          data: (context, records) {
            final summary = AttendanceMonthSummary.of(records, DateTime.now());
            final ratio = summary.presentRatio;
            return Row(children: [
              DonutChart(percent: (ratio ?? 0) * 100, color: palette.primary, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This month',
                        style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.text)),
                    const SizedBox(height: 2),
                    Text(
                      summary.total == 0 ? 'No classes yet' : '${summary.present}/${summary.total} classes',
                      style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                    ),
                  ],
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _DueCard extends ConsumerWidget {
  const _DueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(_myFeeDueProvider);
    final due = async.valueOrNull;
    final clear = due != null && due.amount <= 0;
    final color = clear ? palette.paidManual : palette.notPaid;
    final soft = clear ? palette.paidManualSoft : palette.notPaidSoft;
    final head = due == null
        ? 'Fees'
        : clear
            ? 'All paid'
            : due.due != null ? 'Due ${due.due!.day} ${monthsShort[due.due!.month - 1]}' : 'Fee due';
    return Pressable(
      onTap: () => context.findAncestorStateOfType<AppShellState>()?.goToErpTab(3),
      borderRadius: AppRadii.all(AppRadii.x3l),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: AppRadii.all(AppRadii.x3l),
          border: Border.all(color: color.withValues(alpha: 0.27)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(head, style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: color)),
            const SizedBox(height: 3),
            Text(due == null ? '—' : money(due.amount),
                style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.heavy, color: palette.text)),
            if (due?.line != null && !clear) ...[
              const SizedBox(height: 2),
              Text(due!.line!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
            ],
          ],
        ),
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

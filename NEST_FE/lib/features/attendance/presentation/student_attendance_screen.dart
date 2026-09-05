import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/flip_toggle.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/attendance/data/student_attendance.dart';

/// Which records the day list shows.
enum AttendanceFilter {
  all('All'),
  present('Present'),
  absent('Absent');

  const AttendanceFilter(this.label);
  final String label;
}

/// One student's attendance history, month by month, with any day correctable in place.
///
/// Corrections happen here rather than by reopening the class: a mistake is almost always noticed
/// while looking at a student ("she was here last Tuesday"), and making someone navigate back to
/// the right class to fix it is how wrong records survive.
class StudentAttendanceScreen extends ConsumerStatefulWidget {
  const StudentAttendanceScreen({
    super.key,
    required this.membershipId,
    required this.studentName,
  });

  final String membershipId;
  final String studentName;

  @override
  ConsumerState<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends ConsumerState<StudentAttendanceScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AttendanceFilter _filter = AttendanceFilter.all;
  bool _busy = false;

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Future<void> _correct(StudentAttendanceRecord record) async {
    if (_busy) return;
    setState(() => _busy = true);
    final flipped = record.status == AttendanceStatus.present
        ? AttendanceStatus.absent
        : AttendanceStatus.present;
    try {
      // Submitting a one-entry sheet: the endpoint upserts per student, so correcting one person
      // leaves everyone else's record untouched.
      await ref.read(attendanceApiProvider).submitSheet(
            record.classInstanceId,
            {widget.membershipId: flipped.wire},
          );
      ref.invalidate(studentAttendanceProvider(widget.membershipId));
      if (mounted) {
        showAppToast(context,
            'Marked ${flipped.label} for ${formatFeeDate(record.date)}');
      }
    } catch (e) {
      if (mounted) {
        // The backend refuses a Trainer's edit outside the same-day window, and says so - that
        // message is the useful one, so it is shown as-is.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(studentAttendanceProvider(widget.membershipId));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Row(
          children: [
            PersonAvatar(
                name: widget.studentName, seed: widget.membershipId, size: 30),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(widget.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: AppType.bold,
                      color: palette.text)),
            ),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4l),
            child: Text(e.toString().replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
          ),
        ),
        data: (all) {
          final summary = AttendanceMonthSummary.of(all, _month);
          final visible = summary.records.where((r) => switch (_filter) {
                AttendanceFilter.all => true,
                AttendanceFilter.present => r.status == AttendanceStatus.present,
                AttendanceFilter.absent => r.status == AttendanceStatus.absent,
              }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x5l),
            children: [
              _monthNav(palette),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: _StatPill(
                      icon: Icons.check_circle_outline,
                      color: palette.paidManual,
                      soft: palette.paidManualSoft,
                      count: summary.present,
                      label: 'Present',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatPill(
                      icon: Icons.cancel_outlined,
                      color: palette.notPaid,
                      soft: palette.notPaidSoft,
                      count: summary.absent,
                      label: 'Absent',
                    ),
                  ),
                ],
              ),
              if (summary.presentRatio != null) ...[
                const SizedBox(height: AppSpacing.md),
                _attendanceBar(palette, summary),
              ],
              const SizedBox(height: AppSpacing.x4l),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('DAYS', style: AppType.sectionLabel(palette.textMuted)),
                  Row(
                    children: [
                      for (final filter in AttendanceFilter.values) ...[
                        _FilterPill(
                          label: filter.label,
                          selected: _filter == filter,
                          color: switch (filter) {
                            AttendanceFilter.all => palette.primary,
                            AttendanceFilter.present => palette.paidManual,
                            AttendanceFilter.absent => palette.notPaid,
                          },
                          soft: switch (filter) {
                            AttendanceFilter.all => palette.primarySoft,
                            AttendanceFilter.present => palette.paidManualSoft,
                            AttendanceFilter.absent => palette.notPaidSoft,
                          },
                          onTap: () => setState(() => _filter = filter),
                        ),
                        if (filter != AttendanceFilter.absent)
                          const SizedBox(width: AppSpacing.xs),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x5l),
                  child: Text(
                    summary.total == 0
                        ? 'Nothing recorded for this month yet.'
                        : 'No ${_filter.label.toLowerCase()} days this month.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
                  ),
                )
              else ...[
                for (final record in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _DayRow(
                      record: record,
                      busy: _busy,
                      onFlip: () => _correct(record),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text('Tap Present / Absent on any day to correct a mistake.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _monthNav(AppPalette palette) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AppIconButton(icon: Icons.chevron_left, onTap: () => _shiftMonth(-1)),
        Text('${monthsFull[_month.month - 1]} ${_month.year}',
            style: TextStyle(
                fontSize: 15, fontWeight: AppType.heavy, color: palette.text)),
        AppIconButton(icon: Icons.chevron_right, onTap: () => _shiftMonth(1)),
      ],
    );
  }

  /// A single proportion bar. Shown only when something is recorded - a full red bar for a month
  /// nobody has marked yet would read as an attendance problem rather than a data gap.
  Widget _attendanceBar(AppPalette palette, AttendanceMonthSummary summary) {
    final ratio = summary.presentRatio!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadii.all(AppRadii.xs),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: (ratio * 1000).round().clamp(0, 1000),
                  child: ColoredBox(color: palette.paidManual),
                ),
                Expanded(
                  flex: ((1 - ratio) * 1000).round().clamp(0, 1000),
                  child: ColoredBox(color: palette.notPaid),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${(ratio * 100).round()}% attendance · ${summary.total} '
          'class${summary.total == 1 ? '' : 'es'} recorded',
          style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.color,
    required this.soft,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: color.withValues(alpha: 0.27)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text('$count',
              style: TextStyle(
                  fontSize: AppType.x3l,
                  fontWeight: AppType.heavy,
                  height: 1,
                  color: color)),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.base,
                  fontWeight: AppType.bold,
                  letterSpacing: 0.3,
                  height: 1,
                  color: color,
                )),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.soft,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? soft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: selected ? color : palette.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: AppType.sm,
              fontWeight: AppType.bold,
              color: selected ? color : palette.textMuted,
            )),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.record, required this.busy, required this.onFlip});

  final StudentAttendanceRecord record;
  final bool busy;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final present = record.status == AttendanceStatus.present;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatFeeDate(record.date),
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.medium,
                        color: palette.text)),
                if (record.batchName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      [record.batchName, record.courseName]
                          .whereType<String>()
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.xs, color: palette.textFaint),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FlipToggle(
            isOn: present,
            onLabel: 'Present',
            offLabel: 'Absent',
            onColor: palette.paidManual,
            onSoftColor: palette.paidManualSoft,
            offColor: palette.notPaid,
            offSoftColor: palette.notPaidSoft,
            onIcon: Icons.check_circle_outline,
            offIcon: Icons.cancel_outlined,
            width: 92,
            height: 30,
            onTap: busy ? null : onFlip,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/inline_month_calendar.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// One day of the merged class calendar, filtered down to the caller's active academy.
///
/// `/schedule/feed` is already scoped to the active membership, so unlike the old
/// `/calendar/classes`-backed version of this card, no manual academy filter is needed here.
///
/// Padded a week on each side of the visible month so the week-strip never runs off the edge of
/// fetched data when it's centred near a month boundary.
class TodaysScheduleCard extends ConsumerStatefulWidget {
  const TodaysScheduleCard({super.key});

  @override
  ConsumerState<TodaysScheduleCard> createState() => _TodaysScheduleCardState();
}

class _TodaysScheduleCardState extends ConsumerState<TodaysScheduleCard> {
  late DateTime _monthCursor = _startOfMonth(DateTime.now());
  late DateTime _selectedDay = _dateOnly(DateTime.now());
  bool _expanded = false;

  bool get _isToday => _sameDay(_selectedDay, DateTime.now());

  String get _dayLabel {
    if (_isToday) return "Today's schedule";
    final d = _selectedDay;
    return '${d.day} ${monthsShort[d.month - 1]} ${d.year}';
  }

  ScheduleFeedKey get _feedKey => (
        from: _startOfMonth(_monthCursor).subtract(const Duration(days: 7)),
        to: _endOfMonth(_monthCursor).add(const Duration(days: 7)),
        courseId: null,
      );

  void _selectDay(DateTime day) => setState(() {
        _selectedDay = _dateOnly(day);
        _monthCursor = _startOfMonth(day);
      });

  void _shiftMonth(int delta) => setState(() {
        _monthCursor = DateTime(_monthCursor.year, _monthCursor.month + delta, 1);
        _selectedDay = _monthCursor;
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = ref.watch(sessionControllerProvider).user;
    final canOpenAttendance =
        user != null && (user.isActiveAcademyAdmin || user.hasFeature(FeatureKeys.attendance));
    final feedAsync = ref.watch(scheduleFeedProvider(_feedKey));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: feedAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
          ),
        ),
        data: (entries) {
          final meeting = entries.where((e) => e.status.meets).toList();
          final daySchedule = meeting.where((e) => _sameDay(e.date, _selectedDay)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _dayLabel,
                          style: TextStyle(
                              fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text),
                        ),
                        if (_isToday) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${daySchedule.length} batch${daySchedule.length == 1 ? '' : 'es'} today',
                            style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded ? 'Collapse' : 'Full calendar',
                            style: TextStyle(
                                fontSize: AppType.sm,
                                fontWeight: AppType.bold,
                                color: palette.primary),
                          ),
                          const SizedBox(width: 2),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: AppMotion.chevron,
                            child: Icon(Icons.keyboard_arrow_down, size: 16, color: palette.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AnimatedSize(
                duration: AppMotion.collapse,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _fullCalendar(palette, meeting)
                    : _weekStrip(palette, meeting),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: palette.borderSoft),
              const SizedBox(height: AppSpacing.sm),
              if (daySchedule.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    'No batches scheduled on this day.',
                    style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < daySchedule.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: palette.borderSoft),
                      _ClassRow(
                        entry: daySchedule[i],
                        onTap: canOpenAttendance ? () => context.push('/erp/attendance') : null,
                      ),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _weekStrip(AppPalette palette, List<ScheduleEntry> meeting) {
    final startOfWeek = _selectedDay.subtract(Duration(days: _selectedDay.weekday % 7));
    final week = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    const weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final today = DateTime.now();

    return Row(
      key: const ValueKey('week'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in week)
          _WeekDayCell(
            day: d,
            label: weekdayLabels[d.weekday % 7],
            isSelected: _sameDay(d, _selectedDay),
            isToday: _sameDay(d, today),
            dots: meeting
                .where((e) => _sameDay(e.date, d))
                .take(3)
                .map((e) => e.courseCategory.meta(palette).color)
                .toList(),
            onTap: () => _selectDay(d),
          ),
      ],
    );
  }

  Widget _fullCalendar(AppPalette palette, List<ScheduleEntry> meeting) {
    final dayInfo = <String, CalendarDayInfo>{};
    final dots = <String, List<Color>>{};
    for (final entry in meeting) {
      if (entry.date.year != _monthCursor.year || entry.date.month != _monthCursor.month) continue;
      dots.putIfAbsent(_key(entry.date), () => []).add(entry.courseCategory.meta(palette).color);
    }
    for (final key in dots.keys) {
      dayInfo[key] =
          CalendarDayInfo(dots: dots[key]!, hasRescheduled: false, hasCancelled: false);
    }

    return Padding(
      key: const ValueKey('month'),
      padding: const EdgeInsets.only(top: 2),
      child: InlineMonthCalendar(
        month: _monthCursor,
        selectedDay: _selectedDay,
        dayInfo: dayInfo,
        legend: const [],
        onSelectDay: _selectDay,
        onPrevMonth: () => _shiftMonth(-1),
        onNextMonth: () => _shiftMonth(1),
      ),
    );
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.day,
    required this.label,
    required this.isSelected,
    required this.isToday,
    required this.dots,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isSelected;
  final bool isToday;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.bold,
                color: palette.textFaint,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? palette.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: palette.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight:
                      isSelected || isToday ? AppType.heavy : AppType.semi,
                  color: isSelected
                      ? palette.onPrimary
                      : isToday
                          ? palette.primary
                          : palette.text,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final color in dots)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.entry, this.onTap});

  final ScheduleEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: entry.courseCategory.meta(palette).color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${entry.courseName ?? 'Course'} · ${entry.batchName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.base, fontWeight: AppType.semi, color: palette.text),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${entry.instructorSummary} · ${entry.studentCount} student${entry.studentCount == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                  ),
                ],
              ),
            ),
            Text(
              entry.startTime,
              style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

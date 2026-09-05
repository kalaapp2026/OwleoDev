import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/attendance/presentation/mark_attendance_screen.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';

/// The Attendance tab: pick a day, see the classes on it, open one to mark.
///
/// Driven by the schedule feed rather than its own endpoint - a class is a class, and having two
/// sources for "what is on today" is how the two screens drift apart. The feed carries whether
/// each session has been marked, which is the one thing this screen adds on top.
class AttendanceHomeScreen extends ConsumerStatefulWidget {
  const AttendanceHomeScreen({super.key});

  @override
  ConsumerState<AttendanceHomeScreen> createState() => _AttendanceHomeScreenState();
}

class _AttendanceHomeScreenState extends ConsumerState<AttendanceHomeScreen> {
  late DateTime _date = _dateOnly(DateTime.now());
  String? _courseFilterId;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// One day at a time. The feed is keyed by range, so asking for a single day keeps each day's
  /// result cached separately as the user steps back and forth.
  ScheduleFeedKey get _feedKey =>
      (from: _date, to: _date, courseId: _courseFilterId);

  void _shiftDay(int delta) =>
      setState(() => _date = _date.add(Duration(days: delta)));

  Future<void> _openMarking(ScheduleEntry entry) async {
    final marked = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MarkAttendanceScreen(entry: entry),
    ));
    if (marked == true) ref.invalidate(scheduleFeedProvider(_feedKey));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final feedAsync = ref.watch(scheduleFeedProvider(_feedKey));
    // Scoped to the courses this caller holds Attendance on, so a Trainer granted one course
    // isn't offered the rest in the filter.
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.attendance));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
              child: Column(
                children: [
                  _courseFilter(palette, coursesAsync.valueOrNull ?? const []),
                  const SizedBox(height: AppSpacing.md),
                  _dateNav(palette),
                ],
              ),
            ),
            Expanded(
              child: feedAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4l),
                    child: Text(e.toString().replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: AppType.lg, color: palette.textMuted)),
                  ),
                ),
                data: (entries) {
                  // Cancelled sessions and vacated slots are excluded: there is nobody to mark
                  // for a class that isn't happening.
                  final classes =
                      entries.where((e) => e.status.meets).toList();
                  return _dayList(palette, classes);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Attendance',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: AppType.bold,
                  letterSpacing: -0.2,
                  color: palette.text)),
          const SizedBox(height: 2),
          Text(_longDate(_date),
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
        ],
      ),
    );
  }

  Widget _courseFilter(AppPalette palette, List<Course> courses) {
    final selectable = courses.where((c) => c.isActive).toList();
    final selected = selectable.where((c) => c.id == _courseFilterId).firstOrNull;
    final meta = selected?.category.meta(palette);

    return AttachedSelect<Course?>(
      label: 'Course',
      options: <Course?>[null, ...selectable],
      labelOf: (c) => c?.name ?? 'All courses',
      value: selected,
      panelWidth: 260,
      onSelected: (c) => setState(() => _courseFilterId = c?.id),
      optionBuilder: (context, option, _) {
        if (option == null) {
          return Text('All courses',
              style: TextStyle(
                fontSize: AppType.xl,
                fontWeight: _courseFilterId == null ? AppType.bold : AppType.regular,
                color: _courseFilterId == null ? palette.primary : palette.text,
              ));
        }
        final m = option.category.meta(palette);
        final isSelected = option.id == _courseFilterId;
        return Row(
          children: [
            CourseIcon.forCourse(
                iconKey: option.iconKey,
                category: option.category,
                color: m.color,
                size: 15),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.xl,
                    fontWeight: isSelected ? AppType.bold : AppType.regular,
                    color: isSelected ? m.color : palette.text,
                  )),
            ),
          ],
        );
      },
      triggerBuilder: (context, isOpen, toggle) => Pressable(
        onTap: toggle,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: meta?.color ?? palette.border),
          ),
          child: Row(
            children: [
              if (selected != null)
                CourseIcon.forCourse(
                    iconKey: selected.iconKey,
                    category: selected.category,
                    color: meta!.color,
                    size: 16)
              else
                Icon(Icons.groups_outlined, size: 16, color: palette.textMuted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(selected?.name ?? 'All courses',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: AppType.bold,
                      color: meta?.color ?? palette.text,
                    )),
              ),
              Icon(Icons.keyboard_arrow_down, size: 15, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateNav(AppPalette palette) {
    final isToday = _dateOnly(DateTime.now()) == _date;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.chevron_left,
            onTap: () => _shiftDay(-1),
            size: 30,
            iconSize: 15,
          ),
          Expanded(
            child: Pressable(
              onTap: () async {
                final picked = await showAppCalendar(
                    context: context, month: _date, selectedDay: _date.day);
                if (picked != null && mounted) setState(() => _date = picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 14, color: palette.primary),
                    const SizedBox(width: 7),
                    Text(isToday ? 'Today' : formatFeeDate(_date),
                        style: TextStyle(
                            fontSize: AppType.md,
                            fontWeight: AppType.bold,
                            color: palette.text)),
                  ],
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.chevron_right,
            onTap: () => _shiftDay(1),
            size: 30,
            iconSize: 15,
          ),
        ],
      ),
    );
  }

  Widget _dayList(AppPalette palette, List<ScheduleEntry> classes) {
    if (classes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Text(
            _courseFilterId == null
                ? 'No classes scheduled on this day.'
                : 'No classes for this course on this day.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
          ),
        ),
      );
    }

    final today = DateTime.now();
    final unmarked = classes
        .where((c) => c.attendanceChip(today) == AttendanceChip.notMarked)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.listBottom),
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.xxs, bottom: AppSpacing.md),
          child: Text(
            unmarked == 0
                ? 'ALL CLASSES MARKED'
                : '$unmarked CLASS${unmarked == 1 ? '' : 'ES'} STILL TO MARK',
            style: AppType.sectionLabel(
                unmarked == 0 ? palette.paidManual : palette.gold),
          ),
        ),
        for (final entry in classes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ClassRow(
              entry: entry,
              onTap: () => _openMarking(entry),
            ),
          ),
      ],
    );
  }

  String _longDate(DateTime d) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${monthsShort[d.month - 1]} ${d.year}';
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.entry, required this.onTap});

  final ScheduleEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = entry.courseCategory.meta(palette);
    final chip = entry.attendanceChip(DateTime.now());

    return Pressable(
      // A future class opens read-only rather than being inert: seeing the roster before a class
      // is useful, marking it is what has to wait.
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: meta.soft,
                    borderRadius: AppRadii.all(AppRadii.lg),
                  ),
                  child: CourseIcon.forCourse(
                    iconKey: entry.courseIconKey,
                    category: entry.courseCategory,
                    color: meta.color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.batchName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppType.xxl,
                              fontWeight: AppType.semi,
                              color: palette.text)),
                      const SizedBox(height: 2),
                      Text(entry.courseName ?? 'Unlinked course',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppType.smd,
                              fontWeight: AppType.medium,
                              color: meta.color)),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.timeRange} · ${entry.studentCount} student'
                        '${entry.studentCount == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppType.xs, color: palette.textFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: chip.softColor(palette),
                    borderRadius: AppRadii.all(AppRadii.sm),
                  ),
                  child: Text(chip.label,
                      style: TextStyle(
                        fontSize: AppType.tiny,
                        fontWeight: AppType.bold,
                        color: chip.color(palette),
                      )),
                ),
              ],
            ),
            if (entry.isTemporary)
              Positioned(
                top: -AppSpacing.lg,
                right: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.gold,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(7),
                      bottomRight: Radius.circular(7),
                    ),
                  ),
                  child: Text('TEMPORARY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: AppType.heavy,
                        letterSpacing: 0.4,
                        color: palette.onGold,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

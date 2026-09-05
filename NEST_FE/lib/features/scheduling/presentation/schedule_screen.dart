import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/scheduling/presentation/class_detail_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/recurring_change_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/inline_month_calendar.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/schedule_action_sheets.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/schedule_row.dart';

/// How far the list view looks ahead. The calendar view is unbounded by month instead - a month
/// can reach past this window, and clipping it would leave gaps in the grid.
const scheduleWindowDays = 30;

/// Which subset of the feed is showing.
enum ScheduleStatusFilter { all, changed, cancelled }

/// Calendar (default) or the chronological list.
enum ScheduleViewMode { calendar, list }

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  ScheduleViewMode _view = ScheduleViewMode.calendar;
  ScheduleStatusFilter _statusFilter = ScheduleStatusFilter.all;
  String? _courseFilterId;
  String? _kebabFor;

  late DateTime _monthCursor = _startOfMonth(DateTime.now());
  late DateTime _selectedDay = _dateOnly(DateTime.now());

  bool _busy = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  /// The window each view needs. The calendar asks for its whole visible month; the list asks
  /// for a rolling 30 days from today.
  ScheduleFeedKey get _feedKey {
    final from = _view == ScheduleViewMode.calendar
        ? _startOfMonth(_monthCursor)
        : _dateOnly(DateTime.now());
    final to = _view == ScheduleViewMode.calendar
        ? _endOfMonth(_monthCursor)
        : _dateOnly(DateTime.now()).add(const Duration(days: scheduleWindowDays));
    return (from: from, to: to, courseId: _courseFilterId);
  }

  void _refresh() => ref.invalidate(scheduleFeedProvider(_feedKey));

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  bool _matchesFilter(ScheduleEntry entry) => switch (_statusFilter) {
        ScheduleStatusFilter.all => true,
        ScheduleStatusFilter.changed => entry.status.isChanged,
        ScheduleStatusFilter.cancelled => entry.status == ScheduleEntryStatus.cancelled,
      };

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<void> _handleAction(ScheduleAction action, ScheduleEntry entry) async {
    setState(() => _kebabFor = null);
    if (_busy) return;

    switch (action) {
      case ScheduleAction.reschedule:
        await _reschedule(entry);
      case ScheduleAction.cancel:
        await _cancel(entry);
      case ScheduleAction.swap:
        await _swap(entry);
      case ScheduleAction.recurring:
        await _openRecurring(entry);
      case ScheduleAction.restore:
        await _run(() => ref
            .read(schedulingApiProvider)
            .restoreClass(entry.classInstanceId), 'Class restored');
      case ScheduleAction.undoSwap:
        await _run(() => ref.read(schedulingApiProvider).undoSwap(entry.classInstanceId),
            'Substitute removed');
      case ScheduleAction.undoReschedule:
        await _run(
            () => ref.read(schedulingApiProvider).undoReschedule(entry.classInstanceId),
            'Reschedule undone');
      case ScheduleAction.viewBatch:
        if (mounted) {
          showAppToast(context, 'Opens Batches → Edit "${entry.batchName}"');
        }
    }
  }

  Future<void> _run(Future<void> Function() call, String successMessage) async {
    setState(() => _busy = true);
    try {
      await call();
      _refresh();
      if (mounted) showAppToast(context, successMessage);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reschedule(ScheduleEntry entry) async {
    final outcome = await showRescheduleSheet(context: context, entry: entry);
    if (outcome == null || !mounted) return;
    await _run(
      () => ref.read(schedulingApiProvider).reschedule(
            classInstanceId: entry.classInstanceId,
            newDate: SchedulingApi.isoDate(outcome.newDate),
            newStartTime: outcome.newStartTime.wire,
            newEndTime: outcome.newEndTime.wire,
            reason: outcome.reason,
          ),
      'Class moved to ${formatFeeDate(outcome.newDate)}',
    );
  }

  Future<void> _cancel(ScheduleEntry entry) async {
    final reason = await showCancelClassSheet(context: context, entry: entry);
    if (reason == null || !mounted) return;
    await _run(
      () => ref
          .read(schedulingApiProvider)
          .cancelClass(classInstanceId: entry.classInstanceId, reason: reason),
      'Class cancelled',
    );
  }

  Future<void> _swap(ScheduleEntry entry) async {
    if (entry.courseId == null) return;
    // Candidates come from the course, not the batch: covering for someone usually means pulling
    // in a trainer who teaches the course but not this particular batch.
    final trainers = await ref.read(trainersForCourseProvider(entry.courseId!).future);
    if (!mounted) return;

    final substituteId = await showSwapInstructorSheet(
      context: context,
      entry: entry,
      candidates: [
        for (final t in trainers)
          SchedulePerson(membershipId: t.membershipId, name: t.fullName)
      ],
    );
    if (substituteId == null || !mounted) return;

    final name = trainers
        .where((t) => t.membershipId == substituteId)
        .map((t) => t.fullName)
        .firstOrNull;
    await _run(
      () => ref.read(schedulingApiProvider).swapInstructor(
            classInstanceId: entry.classInstanceId,
            substituteMembershipId: substituteId,
          ),
      'Substitute assigned${name == null ? '' : ': $name'}',
    );
  }

  Future<void> _openRecurring(ScheduleEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecurringChangeScreen(entry: entry),
    ));
    if (changed == true) {
      _refresh();
      if (mounted) showAppToast(context, 'Schedule updated');
    }
  }

  Future<void> _openDetail(ScheduleEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ClassDetailScreen(entry: entry),
    ));
    if (changed == true) _refresh();
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final feedAsync = ref.watch(scheduleFeedProvider(_feedKey));
    // Scoped to the caller's own courses - a Trainer granted one course must not be offered
    // the rest in this picker.
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.reschedule));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: feedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Error(error: e),
          data: (entries) {
            final visible = entries.where(_matchesFilter).toList();
            final changedCount = entries.where((e) => e.status.isChanged).length;
            final cancelledCount = entries
                .where((e) => e.status == ScheduleEntryStatus.cancelled)
                .length;

            return GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () => setState(() => _kebabFor = null),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(palette, entries.length, visible.length),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
                    child: Column(
                      children: [
                        _courseFilter(palette, coursesAsync.valueOrNull ?? const []),
                        const SizedBox(height: AppSpacing.md),
                        _statusFilters(palette, changedCount, cancelledCount),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _view == ScheduleViewMode.calendar
                        ? _calendarView(palette, visible)
                        : _listView(palette, visible),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(AppPalette palette, int total, int shown) {
    final subtitle = _view == ScheduleViewMode.calendar
        ? '${monthsFull[_monthCursor.month - 1]} ${_monthCursor.year} · $shown '
            'class${shown == 1 ? '' : 'es'}'
        : 'Next $scheduleWindowDays days · $shown class${shown == 1 ? '' : 'es'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Schedule',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: AppType.bold,
                        letterSpacing: -0.2,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
              ],
            ),
          ),
          _viewToggle(palette),
        ],
      ),
    );
  }

  Widget _viewToggle(AppPalette palette) {
    Widget half(ScheduleViewMode mode, IconData icon, String tooltip) {
      final active = _view == mode;
      return Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: () => setState(() => _view = mode),
          child: AnimatedContainer(
            duration: AppMotion.fade,
            width: 32,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? palette.primary : Colors.transparent,
              borderRadius: AppRadii.all(AppRadii.smd),
            ),
            child: Icon(icon,
                size: 15, color: active ? palette.onPrimary : palette.textMuted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          half(ScheduleViewMode.calendar, Icons.grid_view_rounded, 'Calendar view'),
          const SizedBox(width: 2),
          half(ScheduleViewMode.list, Icons.view_list_rounded, 'List view'),
        ],
      ),
    );
  }

  Widget _courseFilter(AppPalette palette, List<Course> courses) {
    // Already feature-scoped by the provider; only inactive courses still need dropping.
    final selectable = courses.where((c) => c.isActive).toList();
    final selected =
        selectable.where((c) => c.id == _courseFilterId).firstOrNull;
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
              size: 15,
            ),
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
                  size: 16,
                )
              else
                Icon(Icons.groups_outlined, size: 16, color: palette.textMuted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  selected?.name ?? 'All courses',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.xl,
                    fontWeight: AppType.bold,
                    color: meta?.color ?? palette.text,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_down, size: 15, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusFilters(AppPalette palette, int changedCount, int cancelledCount) {
    Widget chip(ScheduleStatusFilter filter, String label, IconData? icon, Color accent,
        Color soft, int count) {
      final active = _statusFilter == filter;
      return Expanded(
        child: Pressable(
          // Tapping the active chip clears back to All, so there's always a way out without
          // hunting for the All chip.
          onTap: () => setState(() =>
              _statusFilter = active ? ScheduleStatusFilter.all : filter),
          child: AnimatedContainer(
            duration: AppMotion.fade,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: active ? soft : palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: active ? accent : palette.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 11, color: active ? accent : palette.textMuted),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    count > 0 && filter != ScheduleStatusFilter.all
                        ? '$label ($count)'
                        : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.sm,
                      fontWeight: AppType.bold,
                      color: active ? accent : palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(ScheduleStatusFilter.all, 'All', null, palette.primary, palette.primarySoft, 0),
        const SizedBox(width: AppSpacing.xs),
        chip(ScheduleStatusFilter.changed, 'Rescheduled', Icons.refresh, palette.gold,
            palette.goldSoft, changedCount),
        const SizedBox(width: AppSpacing.xs),
        chip(ScheduleStatusFilter.cancelled, 'Cancelled', Icons.block, palette.notPaid,
            palette.notPaidSoft, cancelledCount),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Views
  // ------------------------------------------------------------------

  Widget _calendarView(AppPalette palette, List<ScheduleEntry> visible) {
    final dayInfo = <String, CalendarDayInfo>{};
    final dots = <String, List<Color>>{};
    final rescheduled = <String>{};
    final cancelled = <String>{};

    for (final entry in visible) {
      final key = SchedulingApi.isoDate(entry.date);
      if (entry.status == ScheduleEntryStatus.cancelled) cancelled.add(key);
      if (entry.status.isChanged) rescheduled.add(key);
      // Only a class that actually meets earns a dot - a cancelled or vacated slot marks the day
      // through its ring instead.
      if (entry.status.meets) {
        dots.putIfAbsent(key, () => []).add(entry.courseCategory.meta(palette).color);
      }
    }
    for (final key in {...dots.keys, ...rescheduled, ...cancelled}) {
      dayInfo[key] = CalendarDayInfo(
        dots: dots[key] ?? const [],
        hasRescheduled: rescheduled.contains(key),
        hasCancelled: cancelled.contains(key),
      );
    }

    final selectedKey = SchedulingApi.isoDate(_selectedDay);
    final dayRows = visible
        .where((e) => SchedulingApi.isoDate(e.date) == selectedKey)
        .toList();

    // The legend names exactly the categories whose dots appear on the selected day.
    final seen = <CourseCategory>{};
    final legend = <CalendarLegendEntry>[];
    for (final entry in dayRows) {
      if (!entry.status.meets) continue;
      if (!seen.add(entry.courseCategory)) continue;
      legend.add(CalendarLegendEntry(
        label: entry.courseCategory.label,
        color: entry.courseCategory.meta(palette).color,
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xxs, AppSpacing.xl, AppSpacing.listBottom),
      children: [
        InlineMonthCalendar(
          month: _monthCursor,
          selectedDay: _selectedDay,
          dayInfo: dayInfo,
          legend: legend,
          onSelectDay: (d) => setState(() => _selectedDay = d),
          onPrevMonth: () => _shiftMonth(-1),
          onNextMonth: () => _shiftMonth(1),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxs, AppSpacing.sm, AppSpacing.xxs, AppSpacing.sm),
          child: Text(_dayHeading(_selectedDay),
              style: AppType.sectionLabel(palette.textMuted)),
        ),
        if (dayRows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x5l),
            child: Text('No classes on this day.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.lg, color: palette.textFaint)),
          )
        else
          for (final entry in dayRows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _row(entry),
            ),
      ],
    );
  }

  Widget _listView(AppPalette palette, List<ScheduleEntry> visible) {
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Text(
            'No classes match this filter in the next $scheduleWindowDays days.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
          ),
        ),
      );
    }

    // Grouped by date with a sticky-feeling heading per day, rather than a flat list where
    // consecutive days blur together.
    final groups = <DateTime, List<ScheduleEntry>>{};
    for (final entry in visible) {
      groups.putIfAbsent(_dateOnly(entry.date), () => []).add(entry);
    }
    final days = groups.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xxs, AppSpacing.xl, AppSpacing.listBottom),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxs, AppSpacing.md, AppSpacing.xxs, AppSpacing.sm),
              child: Text(_dayHeading(day),
                  style: AppType.sectionLabel(context.palette.textMuted)),
            ),
            for (final entry in groups[day]!)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _row(entry),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
        );
      },
    );
  }

  Widget _row(ScheduleEntry entry) => ScheduleRow(
        entry: entry,
        kebabOpen: _kebabFor == entry.classInstanceId,
        onToggleKebab: () => setState(() => _kebabFor =
            _kebabFor == entry.classInstanceId ? null : entry.classInstanceId),
        onAction: (action) => _handleAction(action, entry),
        onOpenDetail: () => _openDetail(entry),
      );

  void _shiftMonth(int delta) {
    setState(() {
      _monthCursor = DateTime(_monthCursor.year, _monthCursor.month + delta, 1);
      // Landing on the 1st rather than keeping the day number, which would silently skip to a
      // different day when the previous selection doesn't exist in the new month.
      _selectedDay = _monthCursor;
    });
  }

  /// "Today" / "Tomorrow" / "Monday, 7 Sep". Relative labels only for the two nearest days -
  /// past that they stop helping and start making the reader do arithmetic.
  String _dayHeading(DateTime day) {
    final today = _dateOnly(DateTime.now());
    final diff = _dateOnly(day).difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return '${weekdays[day.weekday - 1]}, ${day.day} ${monthsShort[day.month - 1]}';
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Text(
          error.toString().replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.lg, color: palette.textMuted),
        ),
      ),
    );
  }
}

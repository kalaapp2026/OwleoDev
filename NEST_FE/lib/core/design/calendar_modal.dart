import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

/// Sunday-first, matching the calendars people here read.
const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

String monthLabel(DateTime month) => '${_monthNames[month.month - 1]} ${month.year}';

String shortMonthLabel(DateTime month) =>
    '${_monthNames[month.month - 1].substring(0, 3)} ${month.year}';

/// What one day of a marked calendar shows: a dot per item, and optionally a ring round the whole
/// day (the Schedule calendar's way of flagging a cancelled or rescheduled day).
@immutable
class CalendarDayMark {
  const CalendarDayMark({this.dots = const [], this.ring});
  final List<Color> dots;
  final Color? ring;
}

/// Marks per day of a month (keyed by day number), for calendars that need to show what is on each
/// day. Loaded per month, so stepping months fetches the next month's marks.
typedef CalendarMarksLoader = Future<Map<int, CalendarDayMark>> Function(DateTime month);

/// One line of the key under a marked calendar - a filled dot, or a hollow ring when [ring].
@immutable
class CalendarKeyEntry {
  const CalendarKeyEntry(this.label, this.color, {this.ring = false});
  final String label;
  final Color color;
  final bool ring;
}

/// Month grid with prev/next stepping, clamped to a range.
///
/// Returns the chosen date, or null if dismissed. A null [selectedDay] means "the whole month" -
/// the transaction filters use that to mean an unnarrowed month rather than the 1st.
Future<DateTime?> showAppCalendar({
  required BuildContext context,
  required DateTime month,
  int? selectedDay,
  DateTime? earliestMonth,
  DateTime? latestMonth,
  CalendarMarksLoader? marksLoader,
  List<CalendarKeyEntry> marksKey = const [],
  CalendarDayDetailBuilder? dayDetailBuilder,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _CalendarDialog(
      initialMonth: month,
      selectedDay: selectedDay,
      earliestMonth: earliestMonth,
      latestMonth: latestMonth,
      marksLoader: marksLoader,
      marksKey: marksKey,
      dayDetailBuilder: dayDetailBuilder,
    ),
  );
}

/// What to show under the grid once a day is tapped - the Events calendar lists that day's events
/// here. Return null for a day with nothing to show. The dialog's own context is passed so the
/// panel can close the calendar (for example before opening an event).
typedef CalendarDayDetailBuilder = Widget? Function(BuildContext dialogContext, DateTime day);

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({
    required this.initialMonth,
    this.selectedDay,
    this.earliestMonth,
    this.latestMonth,
    this.marksLoader,
    this.marksKey = const [],
    this.dayDetailBuilder,
  });

  final DateTime initialMonth;
  final int? selectedDay;
  final DateTime? earliestMonth;
  final DateTime? latestMonth;
  final CalendarMarksLoader? marksLoader;
  final List<CalendarKeyEntry> marksKey;
  final CalendarDayDetailBuilder? dayDetailBuilder;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

/// Which grid the dialog is showing. Landing straight on a day grid is fine when the target date
/// is nearby, but stepping a birth year back one month at a time is dozens of taps - the year grid
/// gives a direct jump instead.
enum _CalendarView { day, month, year }

class _CalendarDialogState extends State<_CalendarDialog> {
  late DateTime _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  late int? _day = widget.selectedDay;
  _CalendarView _view = _CalendarView.day;
  final ScrollController _yearScrollController = ScrollController();

  Map<int, CalendarDayMark> _marks = const {};
  // Guards against a slow load for a month the user has already stepped away from landing late.
  int _marksRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadMarks();
  }

  Future<void> _loadMarks() async {
    final loader = widget.marksLoader;
    if (loader == null) return;
    final request = ++_marksRequest;
    final month = _month;
    setState(() => _marks = const {});
    try {
      final marks = await loader(month);
      if (mounted && request == _marksRequest) setState(() => _marks = marks);
    } catch (_) {
      // Marks are decoration - a failed load leaves a plain, still-usable calendar.
    }
  }

  int get _earliestYear => (widget.earliestMonth?.year ?? _month.year - 100);
  int get _latestYear => (widget.latestMonth?.year ?? _month.year + 5);
  int _yearIndexOf(int year) => (year - _earliestYear).clamp(0, _latestYear - _earliestYear);

  // Centres roughly on the current month's year rather than leaving the grid at its earliest year
  // - opening the year picker for a decades-old birth date shouldn't itself need scrolling.
  void _scrollYearGridToCurrent() {
    if (!_yearScrollController.hasClients) return;
    const rowHeight = 56.0;
    final row = _yearIndexOf(_month.year) ~/ 4;
    final target = (row * rowHeight - 100).clamp(0.0, _yearScrollController.position.maxScrollExtent);
    _yearScrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _yearScrollController.dispose();
    super.dispose();
  }

  bool get _canGoBack {
    final earliest = widget.earliestMonth;
    return earliest == null || _month.isAfter(DateTime(earliest.year, earliest.month));
  }

  bool get _canGoForward {
    final latest = widget.latestMonth;
    return latest == null || _month.isBefore(DateTime(latest.year, latest.month));
  }

  bool _monthInRange(DateTime month) {
    final earliest = widget.earliestMonth;
    final latest = widget.latestMonth;
    if (earliest != null && month.isBefore(DateTime(earliest.year, earliest.month))) return false;
    if (latest != null && month.isAfter(DateTime(latest.year, latest.month))) return false;
    return true;
  }

  bool _canStepYear(int delta) {
    final year = _month.year + delta;
    return year >= _earliestYear && year <= _latestYear;
  }

  /// Steps the year shown on the month grid, keeping the month. Nothing is loaded yet - that waits
  /// until a month is actually picked.
  void _stepYear(int delta) =>
      setState(() => _month = DateTime(_month.year + delta, _month.month));

  void _step(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      // Stepping months clears the day. Keeping it would silently move the selection to the same
      // date in a different month, which is not what stepping the month asked for.
      _day = null;
    });
    _loadMarks();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Weekday of the 1st, and how many days the month has - DateTime(y, m + 1, 0) is the last day
    // of month m, which handles February and leap years without a special case.
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.x5l),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.x4l),
          border: Border.all(color: palette.border),
          boxShadow: AppShadows.dialog,
        ),
        // Scrolls so the optional day-detail panel can never push the dialog past the screen.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AppIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: switch (_view) {
                    _CalendarView.day => _canGoBack ? () => _step(-1) : null,
                    _CalendarView.month => _canStepYear(-1) ? () => _stepYear(-1) : null,
                    _CalendarView.year => null,
                  },
                ),
                Expanded(
                  child: Center(
                    // The title drills out one level per tap: days -> months -> years, and back from
                    // years to months. The year grid is there so a decades-old date doesn't have to
                    // wait out one chevron tap per month.
                    child: Pressable(
                      onTap: () => setState(() {
                        _view = switch (_view) {
                          _CalendarView.day => _CalendarView.month,
                          _CalendarView.month => _CalendarView.year,
                          _CalendarView.year => _CalendarView.month,
                        };
                        if (_view == _CalendarView.year) {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => _scrollYearGridToCurrent());
                        }
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _view == _CalendarView.day ? monthLabel(_month) : '${_month.year}',
                            style: TextStyle(
                              fontSize: AppType.xxl,
                              fontWeight: AppType.heavy,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _view == _CalendarView.day
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            size: 18,
                            color: palette.textFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: switch (_view) {
                    _CalendarView.day => _canGoForward ? () => _step(1) : null,
                    _CalendarView.month => _canStepYear(1) ? () => _stepYear(1) : null,
                    _CalendarView.year => null,
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_view == _CalendarView.year) ...[
              SizedBox(
                height: 260,
                child: GridView.builder(
                  controller: _yearScrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 48,
                  ),
                  itemCount: _latestYear - _earliestYear + 1,
                  itemBuilder: (context, index) {
                    final year = _earliestYear + index;
                    final selected = year == _month.year;
                    return _YearCell(
                      year: year,
                      selected: selected,
                      // Picking a year lands on the month grid for it, so year then month is two
                      // taps rather than a year followed by a trip back through the chevrons.
                      onTap: () => setState(() {
                        _month = DateTime(year, _month.month);
                        _view = _CalendarView.month;
                      }),
                    );
                  },
                ),
              ),
            ] else if (_view == _CalendarView.month) ...[
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: [
                  for (var m = 1; m <= 12; m++)
                    _MonthCell(
                      label: _monthNames[m - 1].substring(0, 3),
                      selected: m == _month.month,
                      enabled: _monthInRange(DateTime(_month.year, m)),
                      onTap: () {
                        setState(() {
                          _month = DateTime(_month.year, m);
                          // A different month, so the previously picked day no longer applies.
                          _day = null;
                          _view = _CalendarView.day;
                        });
                        _loadMarks();
                      },
                    ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  for (final label in _weekdayLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: AppType.tiny,
                            fontWeight: AppType.bold,
                            color: palette.textFaint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (var i = 0; i < firstWeekday; i++) const SizedBox.shrink(),
                  for (var d = 1; d <= daysInMonth; d++)
                    _DayCell(
                      day: d,
                      selected: d == _day,
                      mark: _marks[d],
                      onTap: () => setState(() => _day = d),
                    ),
                ],
              ),
              if (widget.marksKey.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final k in widget.marksKey)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: k.ring ? 9 : 7,
                            height: k.ring ? 9 : 7,
                            decoration: BoxDecoration(
                              color: k.ring ? Colors.transparent : k.color,
                              shape: BoxShape.circle,
                              border: k.ring ? Border.all(color: k.color, width: 1.5) : null,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            k.label,
                            style: TextStyle(
                              fontSize: AppType.tiny,
                              fontWeight: AppType.medium,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              if (_day != null && widget.dayDetailBuilder != null) ...[
                if (widget.dayDetailBuilder!(context, DateTime(_month.year, _month.month, _day!)) case final detail?) ...[
                  const SizedBox(height: AppSpacing.lg),
                  detail,
                ],
              ],
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                label: 'Done',
                icon: Icons.check,
                onPressed: () => Navigator.of(context).pop(
                  DateTime(_month.year, _month.month, _day ?? 1),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: enabled ? onTap : () {},
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primary : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: selected ? AppType.heavy : AppType.regular,
            color: selected
                ? palette.onPrimary
                : (enabled ? palette.text : palette.textFaint.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}

class _YearCell extends StatelessWidget {
  const _YearCell({required this.year, required this.selected, required this.onTap});

  final int year;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primary : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        child: Text(
          '$year',
          style: TextStyle(
            fontSize: AppType.md,
            fontWeight: selected ? AppType.heavy : AppType.regular,
            color: selected ? palette.onPrimary : palette.text,
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.onTap,
    this.mark,
  });

  final int day;
  final bool selected;
  final CalendarDayMark? mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dots = mark?.dots ?? const <Color>[];
    // The ring is for days that carry a change; the selected day is already filled, so it skips it.
    final ring = selected ? null : mark?.ring;
    return Pressable(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primary : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
          border: ring == null ? null : Border.all(color: ring, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: AppType.md,
                fontWeight: selected ? AppType.heavy : AppType.regular,
                color: selected ? palette.onPrimary : palette.text,
              ),
            ),
            if (dots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots.take(4))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          // On the selected (primary) cell a primary dot would vanish, so every dot
                          // gets a light rim there and stays readable.
                          border: selected ? Border.all(color: palette.onPrimary, width: 1) : null,
                        ),
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

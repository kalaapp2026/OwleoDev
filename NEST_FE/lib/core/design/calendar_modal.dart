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
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _CalendarDialog(
      initialMonth: month,
      selectedDay: selectedDay,
      earliestMonth: earliestMonth,
      latestMonth: latestMonth,
    ),
  );
}

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({
    required this.initialMonth,
    this.selectedDay,
    this.earliestMonth,
    this.latestMonth,
  });

  final DateTime initialMonth;
  final int? selectedDay;
  final DateTime? earliestMonth;
  final DateTime? latestMonth;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

/// Which grid the dialog is showing. Landing straight on a day grid is fine when the target date
/// is nearby, but stepping a birth year back one month at a time is dozens of taps - the year grid
/// gives a direct jump instead.
enum _CalendarView { day, year }

class _CalendarDialogState extends State<_CalendarDialog> {
  late DateTime _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  late int? _day = widget.selectedDay;
  _CalendarView _view = _CalendarView.day;
  final ScrollController _yearScrollController = ScrollController();

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

  void _step(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      // Stepping months clears the day. Keeping it would silently move the selection to the same
      // date in a different month, which is not what stepping the month asked for.
      _day = null;
    });
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AppIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: _view == _CalendarView.day && _canGoBack ? () => _step(-1) : null,
                ),
                Expanded(
                  child: Center(
                    // Tapping the month/year title jumps to a scrollable year grid rather than
                    // making a decades-old date wait out one chevron tap per month.
                    child: Pressable(
                      onTap: () => setState(() {
                        _view = _view == _CalendarView.day ? _CalendarView.year : _CalendarView.day;
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
                  onTap: _view == _CalendarView.day && _canGoForward ? () => _step(1) : null,
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
                      onTap: () => setState(() {
                        _month = DateTime(year, _month.month);
                        _view = _CalendarView.day;
                      }),
                    );
                  },
                ),
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
                      onTap: () => setState(() => _day = d),
                    ),
                ],
              ),
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
  const _DayCell({required this.day, required this.selected, required this.onTap});

  final int day;
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
          '$day',
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

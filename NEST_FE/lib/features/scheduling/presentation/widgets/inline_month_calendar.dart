import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';

/// What one day in the grid needs to render: a dot per class meeting that day, and whether the
/// day carries a change worth ringing.
@immutable
class CalendarDayInfo {
  const CalendarDayInfo({
    required this.dots,
    required this.hasRescheduled,
    required this.hasCancelled,
  });

  /// One colour per class actually meeting, in time order. Cancelled and vacated slots
  /// deliberately contribute no dot - they are not a class taking place - but do set the flags
  /// below, so the day is still marked.
  final List<Color> dots;

  final bool hasRescheduled;
  final bool hasCancelled;

  bool get hasChange => hasRescheduled || hasCancelled;
}

/// A named colour for the legend under the grid.
@immutable
class CalendarLegendEntry {
  const CalendarLegendEntry({required this.label, required this.color});
  final String label;
  final Color color;
}

/// The Schedule tab's month view.
///
/// Swipe left/right changes month alongside the chevrons. The gesture only counts once it has
/// travelled further horizontally than vertically, so an ordinary scroll over the grid is never
/// mistaken for one.
class InlineMonthCalendar extends StatefulWidget {
  const InlineMonthCalendar({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.dayInfo,
    required this.legend,
    required this.onSelectDay,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  /// Any date within the month being shown; only year and month are read.
  final DateTime month;
  final DateTime selectedDay;

  /// Keyed by `yyyy-MM-dd`.
  final Map<String, CalendarDayInfo> dayInfo;

  /// The categories meeting on the selected day - so the legend names exactly what the dots on
  /// that day stand for, rather than a generic "colour = category" note.
  final List<CalendarLegendEntry> legend;

  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  @override
  State<InlineMonthCalendar> createState() => _InlineMonthCalendarState();
}

class _InlineMonthCalendarState extends State<InlineMonthCalendar> {
  static const _swipeThreshold = 42.0;
  Offset? _dragStart;
  bool _handledThisDrag = false;

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final year = widget.month.year;
    final month = widget.month;

    // DateTime(y, m, 0) is the last day of the previous month, so day 0 of the next month gives
    // this month's length without a leap-year special case.
    final daysInMonth = DateTime(year, month.month + 1, 0).day;
    // weekday is 1=Mon..7=Sun; the grid starts on Sunday, so Sunday(7) maps to column 0.
    final firstWeekday = DateTime(year, month.month, 1).weekday % 7;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppIconButton(
                icon: Icons.chevron_left,
                onTap: widget.onPrevMonth,
                size: 30,
                iconSize: 15,
              ),
              Text(
                '${monthsFull[month.month - 1]} $year',
                style: TextStyle(
                  fontSize: AppType.xxl,
                  fontWeight: AppType.heavy,
                  color: palette.text,
                ),
              ),
              AppIconButton(
                icon: Icons.chevron_right,
                onTap: widget.onNextMonth,
                size: 30,
                iconSize: 15,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
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
          GestureDetector(
            onHorizontalDragStart: (d) {
              _dragStart = d.localPosition;
              _handledThisDrag = false;
            },
            onHorizontalDragUpdate: (d) {
              if (_handledThisDrag || _dragStart == null) return;
              final dx = d.localPosition.dx - _dragStart!.dx;
              final dy = d.localPosition.dy - _dragStart!.dy;
              if (dx.abs() < _swipeThreshold || dx.abs() < dy.abs()) return;
              // Fired mid-drag rather than on release: waiting for the end makes the month feel
              // like it lags behind the finger.
              _handledThisDrag = true;
              if (dx < 0) {
                widget.onNextMonth();
              } else {
                widget.onPrevMonth();
              }
            },
            onHorizontalDragEnd: (_) => _dragStart = null,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: AppSpacing.xxs,
                crossAxisSpacing: AppSpacing.xxs,
              ),
              itemCount: firstWeekday + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstWeekday) return const SizedBox.shrink();
                final day = DateTime(year, month.month, index - firstWeekday + 1);
                return _DayCell(
                  day: day,
                  info: widget.dayInfo[_key(day)],
                  isSelected: _sameDay(day, widget.selectedDay),
                  isToday: _sameDay(day, today),
                  onTap: () => widget.onSelectDay(day),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.borderSoft)),
            ),
            child: Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.legend.isEmpty)
                  Text('No classes on this day',
                      style: TextStyle(
                        fontSize: AppType.tiny,
                        fontWeight: AppType.medium,
                        color: palette.textFaint,
                      ))
                else
                  for (final entry in widget.legend)
                    _LegendItem(label: entry.label, color: entry.color, filled: true),
                _LegendItem(label: 'Rescheduled', color: palette.gold, filled: false),
                _LegendItem(label: 'Cancelled', color: palette.notPaid, filled: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.info,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final CalendarDayInfo? info;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dots = info?.dots ?? const <Color>[];

    // Ring priority: today's own ring wins, then a cancellation, then a reschedule. Cancelled
    // outranks rescheduled because it's the one that means a class isn't happening at all.
    final Color? ringColor = isSelected
        ? null
        : isToday
            ? palette.primary
            : info?.hasCancelled == true
                ? palette.notPaid
                : info?.hasRescheduled == true
                    ? palette.gold
                    : null;

    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? palette.primary : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.md),
          border: ringColor == null
              ? Border.all(color: Colors.transparent)
              : Border.all(color: ringColor, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: AppType.base,
                fontWeight: isSelected || isToday ? AppType.heavy : AppType.regular,
                color: isSelected
                    ? palette.onPrimary
                    : isToday
                        ? palette.primary
                        : palette.text,
              ),
            ),
            if (dots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Capped at four with a "+n" overflow - beyond that the dots stop being
                    // countable and just make the cell noisy.
                    for (final color in dots.take(4))
                      Container(
                        width: 4.5,
                        height: 4.5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: isSelected ? palette.onPrimary : color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (dots.length > 4)
                      Text(
                        '+${dots.length - 4}',
                        style: TextStyle(
                          fontSize: 7,
                          height: 1,
                          fontWeight: AppType.heavy,
                          color: isSelected ? palette.onPrimary : palette.textFaint,
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

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color, required this.filled});

  final String label;
  final Color color;

  /// Filled marks a category dot; hollow marks a ring, matching how each appears in the grid.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: filled ? 6 : 8,
          height: filled ? 6 : 8,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.tiny,
            fontWeight: AppType.medium,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

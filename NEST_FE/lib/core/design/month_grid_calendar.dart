import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// How one day of a [MonthGridCalendar] is painted. The calendar owns the grid, month/year
/// drilling and swiping; the caller decides what each day means (attendance status, classes,
/// events) by returning one of these.
@immutable
class MonthCell {
  const MonthCell({
    this.background,
    this.borderColor,
    this.dashed = false,
    this.textColor,
    this.bold = false,
    this.opacity = 1,
    this.dots = const [],
    this.tappable = true,
  });

  final Color? background;
  final Color? borderColor;
  final bool dashed;
  final Color? textColor;
  final bool bold;
  final double opacity;

  /// Up to three small dots under the number.
  final List<Color> dots;
  final bool tappable;
}

enum _GridView { days, months, years }

/// The prototype's month calendar: a 7-column grid of square day cells, a title that drills out to a
/// month grid and then a year grid, and a swipe to step months. [expandedDay] opens a panel
/// ([expandedBuilder]) directly under that day's week, the way the attendance calendar shows a
/// day's details and the home calendar offers "Go to this day".
class MonthGridCalendar extends StatefulWidget {
  const MonthGridCalendar({
    super.key,
    required this.initialMonth,
    required this.cellFor,
    required this.onDayTap,
    this.expandedDay,
    this.expandedBuilder,
    this.onMonthChanged,
    this.accent,
    this.onAccent,
    this.titleSize = 15.5,
    this.firstYear = 2022,
    this.lastYear = 2032,
    this.yearTileColor,
  });

  final DateTime initialMonth;
  final MonthCell Function(DateTime day) cellFor;
  final ValueChanged<DateTime> onDayTap;
  final DateTime? expandedDay;
  final Widget Function(DateTime day)? expandedBuilder;
  final ValueChanged<DateTime>? onMonthChanged;

  /// Fill for the picked month/year. Gold on the student screens, teal on a date picker.
  final Color? accent;
  final Color? onAccent;
  final double titleSize;
  final int firstYear;
  final int lastYear;
  final Color? yearTileColor;

  @override
  State<MonthGridCalendar> createState() => _MonthGridCalendarState();
}

class _MonthGridCalendarState extends State<MonthGridCalendar> {
  late int _year = widget.initialMonth.year;
  late int _month = widget.initialMonth.month;
  _GridView _view = _GridView.days;
  final _yearScroll = ScrollController();

  @override
  void dispose() {
    _yearScroll.dispose();
    super.dispose();
  }

  void _go(int month, int year) {
    setState(() {
      _month = month;
      _year = year;
    });
    widget.onMonthChanged?.call(DateTime(year, month));
  }

  void _prev() => _go(_month == 1 ? 12 : _month - 1, _month == 1 ? _year - 1 : _year);
  void _next() => _go(_month == 12 ? 1 : _month + 1, _month == 12 ? _year + 1 : _year);

  Widget _arrow(IconData icon, VoidCallback onTap) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Icon(icon, size: 16, color: palette.text),
      ),
    );
  }

  Widget _title(String text, VoidCallback onTap) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              style: TextStyle(fontSize: widget.titleSize, fontWeight: AppType.heavy, color: palette.text)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: palette.textFaint),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _GridView.days:
        return _days(context);
      case _GridView.months:
        return _months(context);
      case _GridView.years:
        return _years(context);
    }
  }

  Widget _days(BuildContext context) {
    final palette = context.palette;
    final first = DateTime(_year, _month, 1).weekday % 7;
    final count = DateTime(_year, _month + 1, 0).day;
    final cells = <int?>[...List<int?>.filled(first, null), for (var d = 1; d <= count; d++) d];
    final weeks = <List<int?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      final week = cells.sublist(i, (i + 7).clamp(0, cells.length));
      weeks.add([...week, ...List<int?>.filled(7 - week.length, null)]);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 250) _prev();
        if (v < -250) _next();
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _arrow(Icons.chevron_left, _prev),
          _title('${_monthNames[_month - 1]} $_year', () => setState(() => _view = _GridView.months)),
          _arrow(Icons.chevron_right, _next),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (final l in _weekdayLabels)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(l,
                      style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, color: palette.textFaint)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        for (final week in weeks) ...[
          Row(children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: week[i] == null
                    ? const SizedBox.shrink()
                    : _DayTile(
                        day: week[i]!,
                        cell: widget.cellFor(DateTime(_year, _month, week[i]!)),
                        onTap: () => widget.onDayTap(DateTime(_year, _month, week[i]!)),
                      ),
              ),
            ],
          ]),
          if (widget.expandedDay != null &&
              widget.expandedBuilder != null &&
              week.any((d) => d != null && DateTime(_year, _month, d) == widget.expandedDay))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: widget.expandedBuilder!(widget.expandedDay!),
            ),
          const SizedBox(height: 4),
        ],
      ]),
    );
  }

  Widget _months(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent ?? palette.gold;
    final onAccent = widget.onAccent ?? Colors.white;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _arrow(Icons.chevron_left, () => _go(_month, _year - 1)),
        _title('$_year', () {
          setState(() => _view = _GridView.years);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_yearScroll.hasClients) return;
            final index = (_year - widget.firstYear).clamp(0, widget.lastYear - widget.firstYear);
            _yearScroll.jumpTo((index * 52.0 - 100).clamp(0.0, _yearScroll.position.maxScrollExtent));
          });
        }),
        _arrow(Icons.chevron_right, () => _go(_month, _year + 1)),
      ]),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.1,
        children: [
          for (var m = 1; m <= 12; m++)
            Pressable(
              onTap: () {
                _go(m, _year);
                setState(() => _view = _GridView.days);
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m == _month ? accent : Colors.transparent,
                  borderRadius: AppRadii.all(AppRadii.md),
                ),
                child: Text(_monthNames[m - 1].substring(0, 3),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: m == _month ? AppType.heavy : AppType.semi,
                      color: m == _month ? onAccent : palette.text,
                    )),
              ),
            ),
        ],
      ),
    ]);
  }

  Widget _years(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent ?? palette.gold;
    final onAccent = widget.onAccent ?? Colors.white;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Select year', style: TextStyle(fontSize: 15.5, fontWeight: AppType.heavy, color: palette.text)),
      const SizedBox(height: 14),
      SizedBox(
        height: 240,
        child: ListView.separated(
          controller: _yearScroll,
          itemCount: widget.lastYear - widget.firstYear + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final y = widget.firstYear + i;
            final selected = y == _year;
            return Pressable(
              onTap: () {
                _go(_month, y);
                setState(() => _view = _GridView.months);
              },
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? accent : (widget.yearTileColor ?? palette.surfaceHigh),
                  borderRadius: AppRadii.all(AppRadii.md),
                ),
                child: Text('$y',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? AppType.heavy : AppType.bold,
                      color: selected ? onAccent : palette.text,
                    )),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.cell, required this.onTap});

  final int day;
  final MonthCell cell;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tile = AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        foregroundPainter: cell.dashed && cell.borderColor != null ? _DashedRRect(cell.borderColor!, 10) : null,
        child: Container(
          decoration: BoxDecoration(
            color: cell.background,
            borderRadius: AppRadii.all(AppRadii.md),
            border: !cell.dashed && cell.borderColor != null ? Border.all(color: cell.borderColor!, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.1,
                    fontWeight: cell.bold ? AppType.heavy : FontWeight.w500,
                    color: cell.textColor ?? palette.text,
                  )),
              if (cell.dots.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final c in cell.dots.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
    return Opacity(
      opacity: cell.opacity,
      child: cell.tappable ? GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: tile) : tile,
    );
  }
}

class _DashedRRect extends CustomPainter {
  _DashedRRect(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 3), paint);
        distance += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color || old.radius != radius;
}

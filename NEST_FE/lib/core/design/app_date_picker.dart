import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// A floating date-picker card: day grid by default, drilling into a month grid and then a
/// scrollable year list for fast long-range jumps (a birth year decades back would otherwise be
/// dozens of arrow taps). Deliberately generic - [title], [value], [minDate]/[maxDate] and the
/// returned [DateTime] are all the caller supplies; nothing here assumes it's a birth date.
///
/// Returns the picked date, or null if dismissed (tapped outside, or the system back gesture)
/// without pressing Done.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required String title,
  DateTime? value,
  DateTime? minDate,
  DateTime? maxDate,
}) {
  return showDialog<DateTime>(
    context: context,
    // showDialog's own barrier already dims the form behind and closes on an outside tap -
    // exactly the reference behaviour - so there's no need to build a second one.
    builder: (context) => _AppDatePickerDialog(
      title: title,
      value: value,
      minDate: minDate,
      maxDate: maxDate,
    ),
  );
}

enum _PickerView { day, month, year }

class _AppDatePickerDialog extends StatefulWidget {
  const _AppDatePickerDialog({
    required this.title,
    this.value,
    this.minDate,
    this.maxDate,
  });

  final String title;
  final DateTime? value;
  final DateTime? minDate;
  final DateTime? maxDate;

  @override
  State<_AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<_AppDatePickerDialog> {
  // The month/year currently browsed - independent of [_day], which is the actual selection.
  // Reopening starts here on the selected date's month (or today's, with no value), per spec.
  late DateTime _month;
  int? _day;
  _PickerView _view = _PickerView.day;

  // One key per rendered year row, so the selected one can be scrolled to centre with
  // Scrollable.ensureVisible - simpler and more correct than hand-computing a scroll offset,
  // since it doesn't need to know the viewport's own height.
  final _yearKeys = <int, GlobalKey>{};

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _monthOnly(DateTime d) => DateTime(d.year, d.month);

  int get _minYear => widget.minDate?.year ?? DateTime.now().year - 100;
  int get _maxYear => widget.maxDate?.year ?? DateTime.now().year;

  @override
  void initState() {
    super.initState();
    final seed = widget.value ?? DateTime.now();
    _month = _clampMonth(DateTime(seed.year, seed.month));
    _day = widget.value?.day;
  }

  DateTime _clampMonth(DateTime month) {
    var m = month;
    final min = widget.minDate;
    final max = widget.maxDate;
    if (min != null && m.isBefore(_monthOnly(min))) m = _monthOnly(min);
    if (max != null && m.isAfter(_monthOnly(max))) m = _monthOnly(max);
    return m;
  }

  bool get _canGoBackMonth => widget.minDate == null || _month.isAfter(_monthOnly(widget.minDate!));
  bool get _canGoForwardMonth => widget.maxDate == null || _month.isBefore(_monthOnly(widget.maxDate!));
  bool get _canGoBackYear => _month.year > _minYear;
  bool get _canGoForwardYear => _month.year < _maxYear;

  bool _monthDisabled(int year, int month1based) {
    final candidate = DateTime(year, month1based);
    if (widget.minDate != null && candidate.isBefore(_monthOnly(widget.minDate!))) return true;
    if (widget.maxDate != null && candidate.isAfter(_monthOnly(widget.maxDate!))) return true;
    return false;
  }

  bool _dayDisabled(int day) {
    final candidate = DateTime(_month.year, _month.month, day);
    if (widget.minDate != null && candidate.isBefore(_dateOnly(widget.minDate!))) return true;
    if (widget.maxDate != null && candidate.isAfter(_dateOnly(widget.maxDate!))) return true;
    return false;
  }

  void _stepMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _day = null;
    });
  }

  void _stepYear(int delta) {
    setState(() {
      final target = _clampMonth(DateTime(_month.year + delta, _month.month));
      if (target != _month) _day = null;
      _month = target;
    });
  }

  void _openMonthView() => setState(() => _view = _PickerView.month);

  void _openYearView() {
    setState(() => _view = _PickerView.year);
    // The list only exists once this frame builds - the key lookup has to wait for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _yearKeys[_month.year]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 200));
      }
    });
  }

  void _selectMonth(int month1based) {
    if (_monthDisabled(_month.year, month1based)) return;
    setState(() {
      final target = _clampMonth(DateTime(_month.year, month1based));
      if (target != _month) _day = null;
      _month = target;
      _view = _PickerView.day;
    });
  }

  void _selectYear(int year) {
    setState(() {
      final target = _clampMonth(DateTime(year, _month.month));
      if (target != _month) _day = null;
      _month = target;
      _view = _PickerView.month;
    });
  }

  void _selectDay(int day) {
    if (_dayDisabled(day)) return;
    setState(() => _day = day);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final locale = Localizations.localeOf(context).toString();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.x5l),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x4l),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.x4l),
          border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
          boxShadow: AppShadows.focusGlow(palette.primary),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppType.sectionLabel(palette.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            _header(palette, locale),
            const SizedBox(height: AppSpacing.md),
            // Grows/shrinks smoothly between a 4-row and a 6-row month, and between the day/month
            // grids and the (taller) scrollable year list - AnimatedSwitcher's default fade
            // gives the "quick ~150ms crossfade" the spec allows in place of an instant cut.
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: KeyedSubtree(
                  key: ValueKey(_view),
                  child: switch (_view) {
                    _PickerView.day => _dayView(palette, locale),
                    _PickerView.month => _monthView(palette, locale),
                    _PickerView.year => _yearView(palette, locale),
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _DoneButton(
              // Selecting a month or year alone must never leave the field pointed at some
              // implicit day-1 default - only an actual day tap can enable this.
              enabled: _day != null,
              onTap: () => Navigator.of(context).pop(DateTime(_month.year, _month.month, _day!)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette, String locale) {
    final showArrows = _view != _PickerView.year;
    final label = switch (_view) {
      _PickerView.day => DateFormat.yMMMM(locale).format(_month),
      _PickerView.month => DateFormat.y(locale).format(_month),
      _PickerView.year => 'Select year',
    };
    final onBack = switch (_view) {
      _PickerView.day => _canGoBackMonth ? () => _stepMonth(-1) : null,
      _PickerView.month => _canGoBackYear ? () => _stepYear(-1) : null,
      _PickerView.year => null,
    };
    final onForward = switch (_view) {
      _PickerView.day => _canGoForwardMonth ? () => _stepMonth(1) : null,
      _PickerView.month => _canGoForwardYear ? () => _stepYear(1) : null,
      _PickerView.year => null,
    };
    final onLabelTap = switch (_view) {
      _PickerView.day => _openMonthView,
      _PickerView.month => _openYearView,
      _PickerView.year => null,
    };

    return Row(
      children: [
        if (showArrows)
          _NavChevron(icon: Icons.chevron_left_rounded, onTap: onBack)
        else
          const SizedBox(width: 44),
        Expanded(
          child: Center(
            child: _view == _PickerView.year
                ? Text(
                    label,
                    style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.primary),
                  )
                : Pressable(
                    onTap: onLabelTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style:
                              TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.primary),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: palette.primary),
                      ],
                    ),
                  ),
          ),
        ),
        if (showArrows)
          _NavChevron(icon: Icons.chevron_right_rounded, onTap: onForward)
        else
          const SizedBox(width: 44),
      ],
    );
  }

  /// S M T W T F S, in the current locale - built from a known Sunday rather than a hardcoded
  /// English array, then trimmed to one character to match the reference's single-letter header.
  List<String> _weekdayInitials(String locale) {
    final sunday = DateTime(2024, 1, 7);
    return List.generate(7, (i) {
      final full = DateFormat.E(locale).format(sunday.add(Duration(days: i)));
      return full.substring(0, 1);
    });
  }

  Widget _dayView(AppPalette palette, String locale) {
    // DateTime(y, m, 1).weekday is Monday=1..Sunday=7; %7 turns that into Sunday=0..Saturday=6,
    // matching the Sunday-first grid. DateTime(y, m+1, 0) is the last day of month m, which
    // handles February and leap years without a special case.
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = _dateOnly(DateTime.now());
    final labels = _weekdayInitials(locale);

    return Column(
      key: const ValueKey('day'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textMuted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // A fixed row extent (rather than childAspectRatio) keeps row height constant
          // regardless of the card's own width - the ~48px the spec asks for either way.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 48),
          // No filler for the days before the 1st or after the last - leading cells are blank,
          // and the grid simply ends at daysInMonth, so a 4-week February is shorter than a
          // 6-week month rather than padded out to a uniform row count.
          itemCount: firstWeekday + daysInMonth,
          itemBuilder: (context, index) {
            if (index < firstWeekday) return const SizedBox.shrink();
            final day = index - firstWeekday + 1;
            final date = DateTime(_month.year, _month.month, day);
            final isToday = date == today;
            final isSelected = day == _day;
            final disabled = _dayDisabled(day);
            return _DayCell(
              label: '$day',
              selected: isSelected,
              today: isToday,
              disabled: disabled,
              onTap: disabled ? null : () => _selectDay(day),
            );
          },
        ),
      ],
    );
  }

  Widget _monthView(AppPalette palette, String locale) {
    return GridView.builder(
      key: const ValueKey('month'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisExtent: 52,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        final month1based = index + 1;
        final label = DateFormat.MMM(locale).format(DateTime(_month.year, month1based));
        final selected = month1based == _month.month;
        final disabled = _monthDisabled(_month.year, month1based);
        return _GridChip(
          label: label,
          selected: selected,
          disabled: disabled,
          onTap: disabled ? null : () => _selectMonth(month1based),
        );
      },
    );
  }

  Widget _yearView(AppPalette palette, String locale) {
    final years = List.generate(_maxYear - _minYear + 1, (i) => _minYear + i);
    return SizedBox(
      key: const ValueKey('year'),
      // Tall enough to show ~5 rows with a partial one peeking at each edge (matching the
      // reference), short enough that a century-long list doesn't try to lay out unscrolled.
      height: 300,
      child: ListView.separated(
        itemCount: years.length,
        separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final year = years[index];
          final selected = year == _month.year;
          final key = _yearKeys.putIfAbsent(year, () => GlobalKey());
          return _YearRow(
            key: key,
            label: DateFormat.y(locale).format(DateTime(year)),
            selected: selected,
            onTap: () => _selectYear(year),
          );
        },
      ),
    );
  }
}

class _NavChevron extends StatelessWidget {
  const _NavChevron({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.primary.withValues(alpha: enabled ? 0.4 : 0.15)),
        ),
        child: Icon(icon, size: 22, color: palette.primary.withValues(alpha: enabled ? 1 : 0.35)),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.label,
    required this.selected,
    required this.today,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool today;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textColor = disabled
        ? palette.textFaint
        : selected
            ? palette.onPrimary
            : today
                ? palette.primary
                : palette.text;
    // Pressable fills the whole grid cell (48px tall, and however wide 1/7th of the card is) so
    // the tap target is the full cell rather than just the smaller decorated circle-square drawn
    // inside it - the visual size and the touch target are deliberately different sizes here.
    return Pressable(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.primary : Colors.transparent,
            borderRadius: AppRadii.all(AppRadii.lg),
            border: today && !selected ? Border.all(color: palette.primary, width: 1.5) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppType.md,
              fontWeight: (selected || today) ? AppType.bold : AppType.medium,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// The month grid's cell - unlike [_DayCell], its highlight fills the whole cell (inset only by
/// the grid's own spacing), so it's built directly rather than sharing that widget.
class _GridChip extends StatelessWidget {
  const _GridChip({required this.label, required this.selected, required this.disabled, required this.onTap});

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textColor = disabled ? palette.textFaint : (selected ? palette.onPrimary : palette.text);
    return Pressable(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primary : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.lg),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: textColor),
        ),
      ),
    );
  }
}

class _YearRow extends StatelessWidget {
  const _YearRow({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.primary : palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.lg),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.lg,
            fontWeight: AppType.bold,
            color: selected ? palette.onPrimary : palette.text,
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Reduced opacity rather than AppPrimaryButton's usual grey-out for disabled: picking a
    // month/year without a day must read as "not finished yet", not as a different, inert button.
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.primary,
            borderRadius: AppRadii.all(AppRadii.xl),
            boxShadow: AppShadows.focusGlow(palette.primary),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 18, color: palette.onPrimary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Done',
                style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

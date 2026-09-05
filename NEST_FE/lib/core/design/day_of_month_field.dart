import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';

/// Picks a recurring day of the month (1-31) from a calendar-style grid.
///
/// Collapsed to a single summary row once a day is chosen. A 31-cell grid left permanently open
/// pushes everything below it off a phone screen, and this field appears twice on the course form
/// - billing day and payment-due day - so the cost would be paid twice.
///
/// Deliberately not a date picker: the answer is "the 5th of every cycle", not "5 Sep 2026", and
/// offering a full calendar would invite picking a one-off date that the billing job can't honour.
class DayOfMonthField extends StatefulWidget {
  const DayOfMonthField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accentColor,
    this.clearable = true,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final Color accentColor;

  /// Whether "not set" is a legitimate answer. Billing day uses this to mean "no auto-billing".
  final bool clearable;

  @override
  State<DayOfMonthField> createState() => _DayOfMonthFieldState();
}

class _DayOfMonthFieldState extends State<DayOfMonthField> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (!_open) {
      return Pressable(
        onTap: () => setState(() => _open = true),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.value != null
                      ? widget.accentColor.withValues(alpha: 0.13)
                      : palette.surfaceHigh,
                  borderRadius: AppRadii.all(AppRadii.md),
                ),
                child: Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: widget.value != null ? widget.accentColor : palette.textFaint,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.value == null
                      ? 'Not set'
                      : '${ordinalDay(widget.value!)} of the cycle',
                  style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: AppType.medium,
                    color: widget.value == null ? palette.textFaint : palette.text,
                  ),
                ),
              ),
              Text(
                widget.value == null ? 'Set' : 'Change',
                style: TextStyle(
                  fontSize: AppType.base,
                  fontWeight: AppType.bold,
                  color: palette.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: AppSpacing.xs,
              crossAxisSpacing: AppSpacing.xs,
            ),
            itemCount: 31,
            itemBuilder: (context, index) {
              final day = index + 1;
              final selected = widget.value == day;
              return Pressable(
                onTap: () {
                  widget.onChanged(day);
                  setState(() => _open = false);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? widget.accentColor : palette.surfaceHigh,
                    borderRadius: AppRadii.all(AppRadii.smd),
                    border: Border.all(
                        color: selected ? widget.accentColor : palette.border),
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: AppType.smd,
                      fontWeight: AppType.bold,
                      color: selected ? palette.onPrimary : palette.textMuted,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (widget.clearable && widget.value != null)
                Pressable(
                  onTap: () {
                    widget.onChanged(null);
                    setState(() => _open = false);
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: AppType.base,
                      fontWeight: AppType.medium,
                      color: palette.notPaid,
                    ),
                  ),
                ),
              const Spacer(),
              Pressable(
                onTap: () => setState(() => _open = false),
                child: Text(
                  'Collapse',
                  style: TextStyle(
                    fontSize: AppType.base,
                    fontWeight: AppType.medium,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// A time of day as the pickers deal with it: 24-hour, minute precision, no date attached.
///
/// Dart's own [TimeOfDay] would do, but it formats through the ambient locale and carries no
/// wire representation - and every one of these ends up as an `HH:mm` string on a Java LocalTime.
@immutable
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute);

  /// 0-23.
  final int hour;

  /// 0-59.
  final int minute;

  /// Parses `HH:mm` or `HH:mm:ss`. Returns null for anything else rather than guessing.
  static ClockTime? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return ClockTime(h, m);
  }

  /// `HH:mm` - what the API expects.
  String get wire =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// "4:00 PM".
  String get label {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${minute.toString().padLeft(2, '0')} $period';
  }

  int get hour12 => hour % 12 == 0 ? 12 : hour % 12;
  bool get isPm => hour >= 12;

  int get _asMinutes => hour * 60 + minute;

  @override
  int compareTo(ClockTime other) => _asMinutes.compareTo(other._asMinutes);

  bool operator <(ClockTime other) => _asMinutes < other._asMinutes;
  bool operator <=(ClockTime other) => _asMinutes <= other._asMinutes;
  bool operator >(ClockTime other) => _asMinutes > other._asMinutes;
  bool operator >=(ClockTime other) => _asMinutes >= other._asMinutes;

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => wire;

  static ClockTime fromParts({required int hour12, required int minute, required bool pm}) {
    var h = hour12 % 12;
    if (pm) h += 12;
    return ClockTime(h, minute);
  }
}

/// Opens the clock picker. Resolves to the chosen time, or null if it was cancelled or cleared -
/// [onCleared] distinguishes the two when that matters.
Future<ClockTime?> showAppTimePicker({
  required BuildContext context,
  required String title,
  ClockTime? initial,
  Color? accentColor,
  ClockTime? minTime,
  bool allowClear = true,
}) {
  return showModalBottomSheet<ClockTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (sheetContext) => _TimePickerSheet(
      title: title,
      initial: initial,
      accentColor: accentColor ?? sheetContext.palette.primary,
      minTime: minTime,
      allowClear: allowClear,
    ),
  );
}

const double _clockSize = 300;
const double _clockCentre = _clockSize / 2;
const double _clockRadius = 122;

/// Where a value sits on the dial. 12 o'clock is straight up and values run clockwise, which is
/// why sin drives x and *minus* cos drives y - screen y grows downward.
Offset _valuePosition(int value, int totalTicks, double radius) {
  final radians = (value % totalTicks) * (360 / totalTicks) * math.pi / 180;
  return Offset(
    _clockCentre + radius * math.sin(radians),
    _clockCentre - radius * math.cos(radians),
  );
}

/// The inverse: which tick a tap landed nearest. Distance from the centre is ignored on purpose -
/// a tap anywhere along a spoke means that value, which makes the dial far easier to hit than
/// requiring the ring itself.
int _positionToValue(Offset local, int totalTicks) {
  final dx = local.dx - _clockCentre;
  final dy = local.dy - _clockCentre;
  var degrees = math.atan2(dx, -dy) * 180 / math.pi;
  if (degrees < 0) degrees += 360;
  return (degrees / (360 / totalTicks)).round() % totalTicks;
}

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({
    required this.title,
    required this.initial,
    required this.accentColor,
    required this.minTime,
    required this.allowClear,
  });

  final String title;
  final ClockTime? initial;
  final Color accentColor;
  final ClockTime? minTime;
  final bool allowClear;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _hour12;
  late int _minute;
  late bool _pm;

  /// Which half of the readout the dial is currently editing.
  bool _pickingHour = true;

  /// Dial vs keyboard. The dial only offers five-minute marks; typing is how an exact 4:47 is
  /// reached, so removing it would make some times unpickable.
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    // Seeding from minTime rather than an arbitrary 9:00 when there's no initial value: the end
    // time picker opens straight after the start time is set, and starting it before the start
    // time would open in an entirely disabled state.
    final seed = widget.initial ?? widget.minTime ?? const ClockTime(9, 0);
    _hour12 = seed.hour12;
    _minute = seed.minute;
    _pm = seed.isPm;
  }

  ClockTime get _candidate =>
      ClockTime.fromParts(hour12: _hour12, minute: _minute, pm: _pm);

  bool get _violatesMin => widget.minTime != null && _candidate <= widget.minTime!;

  /// An hour is only unreachable when every minute within it would still fall at or before the
  /// minimum - otherwise picking it and then a later minute is perfectly valid.
  bool _hourDisabled(int hour12) {
    final min = widget.minTime;
    if (min == null) return false;
    return ClockTime.fromParts(hour12: hour12, minute: 59, pm: _pm) <= min;
  }

  bool _minuteDisabled(int minute) {
    final min = widget.minTime;
    if (min == null) return false;
    return ClockTime.fromParts(hour12: _hour12, minute: minute, pm: _pm) <= min;
  }

  void _handleDialTap(Offset local) {
    setState(() {
      if (_pickingHour) {
        final v = _positionToValue(local, 12);
        final hour = v == 0 ? 12 : v;
        if (_hourDisabled(hour)) return;
        _hour12 = hour;
        // Auto-advance: picking an hour almost always means picking a minute next, and the
        // extra tap on the minute field is pure friction.
        _pickingHour = false;
      } else {
        // Snapped to the twelve labelled marks. In-between minutes were fiddly to hit and easy
        // to get wrong by one; the keyboard toggle covers them exactly.
        final minute = _positionToValue(local, 12) * 5;
        if (_minuteDisabled(minute)) return;
        _minute = minute;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accentColor;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.sheetTop,
          border: Border.all(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.4),
                borderRadius: AppRadii.all(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                widget.title.toUpperCase(),
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.heavy,
                  letterSpacing: 0.8,
                  color: accent,
                ),
              ),
            ),
            _readout(palette, accent),
            if (widget.minTime != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4l, AppSpacing.sm, AppSpacing.x4l, 0),
                child: Text(
                  _violatesMin
                      ? 'Must be after ${widget.minTime!.label} - greyed-out times are unavailable'
                      : 'Starts ${widget.minTime!.label}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppType.sm,
                    fontWeight: AppType.medium,
                    color: _violatesMin ? palette.notPaid : palette.textFaint,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.x4l, vertical: _typing ? 0 : AppSpacing.x4l),
              child: _typing ? _typedEntry(palette) : _dial(palette, accent),
            ),
            _footer(palette, accent),
          ],
        ),
      ),
    );
  }

  Widget _readout(AppPalette palette, Color accent) {
    Widget half(String text, bool active, VoidCallback onTap) => Pressable(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 40,
                fontWeight: AppType.heavy,
                height: 1,
                color: active ? accent : palette.text,
              ),
            ),
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x5l, vertical: AppSpacing.x3l),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.19), accent.withValues(alpha: 0.05)],
        ),
        border: Border.symmetric(
          horizontal: BorderSide(color: accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          half(_hour12.toString().padLeft(2, '0'), _pickingHour,
              () => setState(() => _pickingHour = true)),
          Text(':',
              style: TextStyle(
                  fontSize: 40, fontWeight: AppType.heavy, height: 1, color: palette.textFaint)),
          half(_minute.toString().padLeft(2, '0'), !_pickingHour,
              () => setState(() => _pickingHour = false)),
          const SizedBox(width: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(AppRadii.sm),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final isPm in const [false, true])
                  Pressable(
                    onTap: () => setState(() => _pm = isPm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      color: _pm == isPm ? accent : palette.surfaceRaised,
                      child: Text(
                        isPm ? 'PM' : 'AM',
                        style: TextStyle(
                          fontSize: AppType.sm,
                          fontWeight: AppType.heavy,
                          color: _pm == isPm ? palette.onPrimary : palette.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dial(AppPalette palette, Color accent) {
    final selectedValue = _pickingHour ? _hour12 % 12 : _minute;
    final selectedTotal = _pickingHour ? 12 : 60;
    final handEnd = _valuePosition(selectedValue, selectedTotal, _clockRadius - 26);
    final labels = _pickingHour
        ? List.generate(12, (i) => i + 1)
        : List.generate(12, (i) => i * 5);

    return SizedBox(
      width: _clockSize,
      height: _clockSize,
      child: GestureDetector(
        onTapDown: (details) => _handleDialTap(details.localPosition),
        // Dragging around the face tracks continuously, the way a physical dial would.
        onPanUpdate: (details) => _handleDialTap(details.localPosition),
        child: Stack(
          children: [
            Container(
              width: _clockSize,
              height: _clockSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  colors: [accent.withValues(alpha: 0.08), palette.surfaceRaised],
                  stops: const [0, 0.7],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.33), width: 1.5),
              ),
            ),
            CustomPaint(
              size: const Size(_clockSize, _clockSize),
              painter: _DialPainter(
                handEnd: handEnd,
                accent: accent,
                // A minute that isn't on a five-mark gets a small dot instead of the big
                // selection disc, so a typed 4:47 doesn't look like it snapped to 45.
                knobRadius: _pickingHour || _minute % 5 == 0 ? 19 : 6,
              ),
            ),
            for (final value in labels)
              Builder(builder: (context) {
                final pos = _valuePosition(
                  _pickingHour ? value % 12 : value,
                  _pickingHour ? 12 : 60,
                  _clockRadius - 26,
                );
                final isSelected =
                    _pickingHour ? _hour12 % 12 == value % 12 : _minute == value;
                final disabled =
                    _pickingHour ? _hourDisabled(value) : _minuteDisabled(value);
                return Positioned(
                  left: pos.dx - 16,
                  top: pos.dy - 12,
                  width: 32,
                  height: 24,
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: disabled ? 0.35 : 1,
                        child: Text(
                          _pickingHour ? '$value' : value.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: isSelected ? AppType.heavy : AppType.medium,
                            color: disabled
                                ? palette.textFaint
                                : isSelected
                                    ? palette.onPrimary
                                    : palette.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _typedEntry(AppPalette palette) {
    Widget box(String value, ValueChanged<String> onChanged, String caption, int max) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            child: TextField(
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onSubmitted: onChanged,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: TextStyle(
                  fontSize: 38, fontWeight: AppType.heavy, color: palette.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: palette.surfaceRaised,
                contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.x3l),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.xxl),
                  borderSide: BorderSide(color: palette.border, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.xxl),
                  borderSide: BorderSide(color: palette.border, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            caption.toUpperCase(),
            style: TextStyle(
              fontSize: AppType.xs,
              fontWeight: AppType.bold,
              letterSpacing: 0.6,
              color: palette.textFaint,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6l),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(_hour12.toString().padLeft(2, '0'), (v) {
            final n = int.tryParse(v);
            // Clamped rather than rejected: a typed 15 becomes 12 instead of silently doing
            // nothing while the person keeps typing.
            if (n != null) setState(() => _hour12 = n.clamp(1, 12));
          }, 'Hour', 12),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x4l, left: 14, right: 14),
            child: Text(':',
                style: TextStyle(
                    fontSize: 34, fontWeight: AppType.heavy, color: palette.textFaint)),
          ),
          box(_minute.toString().padLeft(2, '0'), (v) {
            final n = int.tryParse(v);
            if (n != null) setState(() => _minute = n.clamp(0, 59));
          }, 'Minute', 59),
        ],
      ),
    );
  }

  Widget _footer(AppPalette palette, Color accent) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.x4l, AppSpacing.xl, AppSpacing.x4l,
          AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          AppIconButton(
            icon: _typing ? Icons.schedule : Icons.keyboard_alt_outlined,
            tooltip: _typing ? 'Switch to clock' : 'Switch to typing',
            onTap: () => setState(() => _typing = !_typing),
            size: 34,
            iconSize: 16,
            color: accent,
          ),
          const Spacer(),
          if (widget.allowClear)
            Pressable(
              // Distinct from Cancel: this clears the value, Cancel leaves whatever was there.
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text('CLEAR',
                    style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.bold,
                        letterSpacing: 0.4,
                        color: palette.notPaid)),
              ),
            ),
          Pressable(
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text('CANCEL',
                  style: TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppType.bold,
                      letterSpacing: 0.4,
                      color: palette.textMuted)),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Pressable(
            onTap: _violatesMin ? null : () => Navigator.of(context).pop(_candidate),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl, vertical: 9),
              decoration: BoxDecoration(
                color: _violatesMin ? palette.surfaceHigh : accent,
                borderRadius: AppRadii.all(AppRadii.md),
              ),
              child: Text(
                'SET',
                style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppType.heavy,
                  letterSpacing: 0.4,
                  color: _violatesMin ? palette.textFaint : palette.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.handEnd,
    required this.accent,
    required this.knobRadius,
  });

  final Offset handEnd;
  final Color accent;
  final double knobRadius;

  @override
  void paint(Canvas canvas, Size size) {
    const centre = Offset(_clockCentre, _clockCentre);
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(centre, handEnd, paint);
    canvas.drawCircle(handEnd, knobRadius, Paint()..color = accent);
    // Painted last so the pivot stays visible on top of the hand.
    canvas.drawCircle(centre, 5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.handEnd != handEnd || old.accent != accent || old.knobRadius != knobRadius;
}

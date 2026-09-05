import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/reason_chips.dart';

/// What a completed reschedule asks the caller to send.
@immutable
class RescheduleOutcome {
  const RescheduleOutcome({
    required this.newDate,
    required this.newStartTime,
    required this.newEndTime,
    required this.reason,
  });

  final DateTime newDate;
  final ClockTime newStartTime;
  final ClockTime newEndTime;
  final String reason;
}

/// Moves one session to another date, optionally at another time. The batch's recurring pattern
/// is untouched - every other occurrence keeps meeting as usual.
Future<RescheduleOutcome?> showRescheduleSheet({
  required BuildContext context,
  required ScheduleEntry entry,
}) {
  return showModalBottomSheet<RescheduleOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (_) => _RescheduleSheet(entry: entry),
  );
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({required this.entry});
  final ScheduleEntry entry;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime _newDate = widget.entry.date.add(const Duration(days: 1));
  late ClockTime? _startTime = ClockTime.tryParse(widget.entry.startTime);
  late ClockTime? _endTime = ClockTime.tryParse(widget.entry.endTime);
  bool _changeTime = false;
  String _reason = scheduleChangeReasons.first;
  String _customReason = '';

  bool get _timeValid =>
      !_changeTime ||
      (_startTime != null && _endTime != null && _startTime! < _endTime!);

  /// Moving a class to the day it is already on is a no-op that would still write an audit entry
  /// and a "rescheduled" badge, so it is refused rather than silently accepted.
  bool get _valid =>
      !_sameDay(_newDate, widget.entry.date) && _timeValid;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.entry.courseCategory.meta(palette).color;

    return _SheetShell(
      icon: Icons.refresh,
      accent: accent,
      title: 'Reschedule class',
      subtitle: '${widget.entry.batchName} · ${widget.entry.courseName ?? ''} — currently '
          '${formatFeeDate(widget.entry.date)}, ${widget.entry.timeRange}',
      content: [
        _FieldLabel('New date'),
        Pressable(
          onTap: () async {
            final picked = await showAppCalendar(
              context: context,
              month: _newDate,
              selectedDay: _newDate.day,
            );
            if (picked != null && mounted) setState(() => _newDate = picked);
          },
          child: _tile(palette, Icons.calendar_today_outlined, accent,
              formatFeeDate(_newDate)),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Also change the time',
                style: TextStyle(
                    fontSize: AppType.md,
                    fontWeight: AppType.semi,
                    color: palette.text)),
            _Switch(
              value: _changeTime,
              accent: accent,
              onChanged: (v) => setState(() => _changeTime = v),
            ),
          ],
        ),
        if (_changeTime) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _timeButton(palette, 'Start', _startTime, accent, () async {
                  final picked = await showAppTimePicker(
                    context: context,
                    title: 'Start time',
                    initial: _startTime,
                    accentColor: accent,
                  );
                  if (mounted) setState(() => _startTime = picked);
                }),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _timeButton(palette, 'End', _endTime, palette.gold, () async {
                  final picked = await showAppTimePicker(
                    context: context,
                    title: 'End time',
                    initial: _endTime,
                    accentColor: palette.gold,
                    minTime: _startTime,
                  );
                  if (mounted) setState(() => _endTime = picked);
                }),
              ),
            ],
          ),
          if (!_timeValid)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('End time must be after start time.',
                  style: TextStyle(fontSize: AppType.sm, color: palette.notPaid)),
            ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _FieldLabel('Reason'),
        ReasonChips(
          selected: _reason,
          customReason: _customReason,
          accent: accent,
          softAccent: widget.entry.courseCategory.meta(palette).soft,
          onSelected: (r) => setState(() => _reason = r),
          onCustomChanged: (v) => setState(() => _customReason = v),
        ),
      ],
      footer: AppPrimaryButton(
        label: 'Reschedule to ${formatFeeDate(_newDate)}',
        icon: Icons.refresh,
        onPressed: _valid
            ? () => Navigator.of(context).pop(RescheduleOutcome(
                  newDate: _newDate,
                  newStartTime: _changeTime
                      ? _startTime!
                      : ClockTime.tryParse(widget.entry.startTime)!,
                  newEndTime:
                      _changeTime ? _endTime! : ClockTime.tryParse(widget.entry.endTime)!,
                  reason: ReasonChips.resolve(_reason, _customReason),
                ))
            : null,
      ),
      footerNote: _valid
          ? null
          : _sameDay(_newDate, widget.entry.date)
              ? 'Pick a different date to move this class to.'
              : 'End time must be after start time.',
    );
  }

  Widget _tile(AppPalette palette, IconData icon, Color accent, String label) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: AppType.bold,
                    color: palette.text)),
          ),
          Icon(Icons.keyboard_arrow_down, size: 15, color: palette.textMuted),
        ],
      ),
    );
  }

  Widget _timeButton(AppPalette palette, String caption, ClockTime? value, Color accent,
      VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(caption,
              style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
        ),
        Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 15, color: accent),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    value?.label ?? 'Set time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.xxl,
                      fontWeight: AppType.bold,
                      color: value == null ? palette.textFaint : palette.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cancels one session, with a reason. The slot stays on the schedule marked cancelled rather
/// than disappearing.
Future<String?> showCancelClassSheet({
  required BuildContext context,
  required ScheduleEntry entry,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (_) => _CancelSheet(entry: entry),
  );
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.entry});
  final ScheduleEntry entry;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  String _reason = scheduleChangeReasons.first;
  String _customReason = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return _SheetShell(
      icon: Icons.block,
      accent: palette.notPaid,
      title: 'Cancel this class',
      subtitle: '${widget.entry.batchName} · ${widget.entry.courseName ?? ''} — '
          '${formatFeeDate(widget.entry.date)}, ${widget.entry.timeRange}. It stays visible here '
          'as cancelled, with the reason below.',
      content: [
        _FieldLabel('Reason'),
        ReasonChips(
          selected: _reason,
          customReason: _customReason,
          accent: palette.notPaid,
          softAccent: palette.notPaidSoft,
          onSelected: (r) => setState(() => _reason = r),
          onCustomChanged: (v) => setState(() => _customReason = v),
        ),
      ],
      footer: Row(
        children: [
          Expanded(
            child: Pressable(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.xl),
                  border: Border.all(color: palette.border, width: 1.5),
                ),
                child: Text('Keep class',
                    style: TextStyle(
                        fontSize: AppType.xl,
                        fontWeight: AppType.bold,
                        color: palette.text)),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppPrimaryButton(
              label: 'Cancel class',
              icon: Icons.block,
              background: palette.notPaid,
              foreground: const Color(0xFF2A0A0C),
              onPressed: () => Navigator.of(context)
                  .pop(ReasonChips.resolve(_reason, _customReason)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Assigns a substitute for one session only.
Future<String?> showSwapInstructorSheet({
  required BuildContext context,
  required ScheduleEntry entry,
  required List<SchedulePerson> candidates,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (_) => _SwapSheet(entry: entry, candidates: candidates),
  );
}

class _SwapSheet extends StatefulWidget {
  const _SwapSheet({required this.entry, required this.candidates});

  final ScheduleEntry entry;
  final List<SchedulePerson> candidates;

  @override
  State<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<_SwapSheet> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.entry.courseCategory.meta(palette).color;

    // Whoever is already teaching it can't be their own substitute.
    final currentIds = widget.entry.instructors.map((i) => i.membershipId).toSet();
    final options =
        widget.candidates.where((c) => !currentIds.contains(c.membershipId)).toList();

    return _SheetShell(
      icon: Icons.manage_accounts_outlined,
      accent: accent,
      title: 'Swap instructor',
      subtitle: '${widget.entry.batchName} · ${formatFeeDate(widget.entry.date)} — usually '
          '${widget.entry.instructorSummary}. This swap applies to this one session only.',
      content: [
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4l),
            child: Text(
              'No other trainers are available for this course.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
            ),
          )
        else
          for (final person in options)
            Pressable(
              onTap: () => setState(() => _selectedId = person.membershipId),
              child: Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: _selectedId == person.membershipId
                      ? accent.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: AppRadii.all(AppRadii.lg),
                ),
                child: Row(
                  children: [
                    PersonAvatar(
                        name: person.name, seed: person.membershipId, size: 32),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.xxl,
                          fontWeight: _selectedId == person.membershipId
                              ? AppType.semi
                              : AppType.regular,
                          color: _selectedId == person.membershipId
                              ? accent
                              : palette.text,
                        ),
                      ),
                    ),
                    if (_selectedId == person.membershipId)
                      Icon(Icons.check, size: 16, weight: 900, color: accent),
                  ],
                ),
              ),
            ),
      ],
      footer: AppPrimaryButton(
        label: 'Confirm substitute',
        icon: Icons.manage_accounts_outlined,
        onPressed:
            _selectedId == null ? null : () => Navigator.of(context).pop(_selectedId),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sheet chrome
// ---------------------------------------------------------------------------

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.content,
    required this.footer,
    this.footerNote,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  /// The scrollable middle of the sheet. Named content rather than children because it is one
  /// slot among several here, not this widget's child list.
  final List<Widget> content;
  final Widget footer;

  /// Explains a disabled footer button. A dead primary action with no reason given is the most
  /// common way a sheet dead-ends.
  final String? footerNote;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
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
                  color: palette.border, borderRadius: AppRadii.all(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, AppSpacing.xxs, AppSpacing.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: accent),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(title,
                            style: TextStyle(
                                fontSize: AppType.xxl,
                                fontWeight: AppType.bold,
                                color: palette.text)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: AppType.base,
                          color: palette.textMuted,
                          height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page,
                  AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.borderSoft)),
              ),
              child: Column(
                children: [
                  footer,
                  if (footerNote != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(footerNote!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: AppType.sm, color: palette.textFaint)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(label.toUpperCase(),
          style: AppType.sectionLabel(context.palette.textMuted)),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.accent, required this.onChanged});

  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.fade,
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: value ? accent : palette.surfaceHigh,
          borderRadius: AppRadii.all(13),
        ),
        child: AnimatedAlign(
          duration: AppMotion.fade,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: value ? palette.onPrimary : palette.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

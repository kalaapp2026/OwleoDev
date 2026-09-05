import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/reason_chips.dart';

/// Changes a batch's recurring pattern from a chosen date onward.
///
/// Distinct from rescheduling one session: everything before the effective date keeps the old
/// pattern (including classes already held), and everything on or after it picks up the new one.
/// The backend closes out the current schedule as of the day before and cancels its not-yet-held
/// future instances, so the change genuinely "continues from here".
///
/// Pops `true` when saved.
class RecurringChangeScreen extends ConsumerStatefulWidget {
  const RecurringChangeScreen({super.key, required this.entry});

  /// The class the change was launched from - supplies the batch and seeds the effective date.
  final ScheduleEntry entry;

  @override
  ConsumerState<RecurringChangeScreen> createState() => _RecurringChangeScreenState();
}

class _RecurringChangeScreenState extends ConsumerState<RecurringChangeScreen> {
  late DateTime _effectiveFrom = widget.entry.date;
  Set<Weekday> _days = {};
  ClockTime? _startTime;
  ClockTime? _endTime;
  late Set<String> _trainerIds = {
    for (final i in widget.entry.instructors) i.membershipId
  };
  String _reason = scheduleChangeReasons.first;
  String _customReason = '';

  bool _prefilled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPattern();
  }

  /// Seeds from the batch's current weekly pattern rather than from the single class this was
  /// launched from - the form is editing the whole recurrence, so opening it showing only the
  /// one day that class falls on would misrepresent what is about to change.
  Future<void> _loadCurrentPattern() async {
    try {
      final slots =
          await ref.read(schedulingApiProvider).currentSchedule(widget.entry.batchId);
      if (!mounted) return;
      setState(() {
        _days = slots.map((s) => Weekday.fromWire(s.dayOfWeek)).toSet();
        if (slots.isNotEmpty) {
          _startTime = ClockTime.tryParse(slots.first.startTime);
          _endTime = ClockTime.tryParse(slots.first.endTime);
        } else {
          _startTime = ClockTime.tryParse(widget.entry.startTime);
          _endTime = ClockTime.tryParse(widget.entry.endTime);
        }
        _prefilled = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _startTime = ClockTime.tryParse(widget.entry.startTime);
          _endTime = ClockTime.tryParse(widget.entry.endTime);
          _prefilled = true;
        });
        _showError(e);
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  bool get _timeValid =>
      _startTime != null && _endTime != null && _startTime! < _endTime!;

  bool get _valid => _days.isNotEmpty && _timeValid && _trainerIds.isNotEmpty;

  String _missing() {
    if (_days.isEmpty) return 'Select at least one day.';
    if (_startTime == null || _endTime == null) return 'Set the start and end time.';
    if (!_timeValid) return 'End time must be after start time.';
    return 'Select at least one instructor.';
  }

  Future<void> _pickTrainers() async {
    if (widget.entry.courseId == null) return;
    final trainers =
        await ref.read(trainersForCourseProvider(widget.entry.courseId!).future);
    if (!mounted) return;
    final chosen = await showPeoplePickerSheet(
      context: context,
      title: 'Select instructors',
      accentColor: widget.entry.courseCategory.meta(context.palette).color,
      searchHint: 'Search instructor',
      people: [
        for (final t in trainers)
          PickablePerson(id: t.membershipId, name: t.fullName, subtitle: t.username)
      ],
      initiallySelected: _trainerIds,
    );
    if (chosen != null && mounted) setState(() => _trainerIds = chosen);
  }

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    try {
      // The trainer set is part of the pattern change, so it is applied to the batch alongside
      // the new slots - otherwise "change schedule going forward" would silently leave the old
      // instructor on every future class.
      final batch = await ref.read(enrolmentApiProvider).getBatch(widget.entry.batchId);
      await ref.read(enrolmentApiProvider).updateBatch(
            widget.entry.batchId,
            name: batch.name,
            description: batch.description,
            trainerMembershipIds: _trainerIds.toList(),
            startDate: batch.startDate,
            endDate: batch.endDate,
            // The roster isn't part of this change; sending it back unchanged keeps the
            // whole-set semantics of updateBatch from emptying it.
            studentMembershipIds:
                await ref.read(enrolmentApiProvider).members(widget.entry.batchId),
          );

      await ref.read(schedulingApiProvider).setSchedule(
            batchId: widget.entry.batchId,
            effectiveFrom: SchedulingApi.isoDate(_effectiveFrom),
            slots: [
              for (final day in _days)
                {
                  'dayOfWeek': day.wire,
                  'startTime': _startTime!.wire,
                  'endTime': _endTime!.wire,
                }
            ],
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = widget.entry.courseCategory.meta(palette);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Change schedule',
                style: TextStyle(
                    fontSize: 17, fontWeight: AppType.bold, color: palette.text)),
            Text('${widget.entry.batchName} · ${widget.entry.courseName ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x5l),
        children: [
          if (!_prefilled)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: palette.surfaceHigh,
                color: palette.primary,
              ),
            ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: meta.soft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: meta.color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Applies going forward only',
                    style: TextStyle(
                        fontSize: AppType.base,
                        fontWeight: AppType.bold,
                        color: meta.color)),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  "Sessions before the effective date keep the batch's current schedule. Every "
                  'session on or after it uses the new pattern below, until changed again.',
                  style: TextStyle(
                      fontSize: AppType.sm, color: palette.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x4l),
          _Field(
            label: 'Effective from',
            child: Pressable(
              onTap: () async {
                final picked = await showAppCalendar(
                  context: context,
                  month: _effectiveFrom,
                  selectedDay: _effectiveFrom.day,
                );
                if (picked != null && mounted) {
                  setState(() => _effectiveFrom = picked);
                }
              },
              child: _tile(palette, Icons.calendar_today_outlined, meta.color,
                  formatFeeDate(_effectiveFrom)),
            ),
          ),
          _Field(
            label: 'Days',
            hint: _days.isEmpty ? 'Select at least one day.' : formatDays(_days),
            child: Row(
              children: [
                for (final day in Weekday.values) ...[
                  Expanded(
                    child: Tooltip(
                      message: day.short,
                      child: Pressable(
                        onTap: () => setState(() {
                          if (!_days.remove(day)) _days.add(day);
                        }),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _days.contains(day)
                                  ? palette.gold
                                  : palette.surfaceRaised,
                              borderRadius: AppRadii.all(AppRadii.smd),
                              border: Border.all(
                                  color: _days.contains(day)
                                      ? palette.gold
                                      : palette.border),
                            ),
                            child: Text(day.initial,
                                style: TextStyle(
                                  fontSize: AppType.base,
                                  fontWeight: AppType.bold,
                                  color: _days.contains(day)
                                      ? palette.onGold
                                      : palette.textMuted,
                                )),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (day != Weekday.sunday) const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
          _Field(
            label: 'Time',
            hint: _startTime != null && _endTime != null && !_timeValid
                ? 'End time must be after start time.'
                : null,
            child: Row(
              children: [
                Expanded(
                  child: _timeTile(palette, 'Start', _startTime, meta.color, () async {
                    final picked = await showAppTimePicker(
                      context: context,
                      title: 'Start time',
                      initial: _startTime,
                      accentColor: meta.color,
                    );
                    if (mounted) setState(() => _startTime = picked);
                  }),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _timeTile(palette, 'End', _endTime, palette.gold, () async {
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
          ),
          _Field(
            label: 'Instructor',
            child: Pressable(
              onTap: _pickTrainers,
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
                    Icon(Icons.person_outline,
                        size: 16,
                        color: _trainerIds.isEmpty ? palette.textFaint : meta.color),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _trainerIds.isEmpty
                            ? 'Select instructor(s)'
                            : '${_trainerIds.length} instructor'
                                '${_trainerIds.length == 1 ? '' : 's'} selected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.xxl,
                          fontWeight: AppType.medium,
                          color: _trainerIds.isEmpty
                              ? palette.textFaint
                              : palette.text,
                        ),
                      ),
                    ),
                    Text(_trainerIds.isEmpty ? 'Select' : 'Edit',
                        style: TextStyle(
                            fontSize: AppType.base,
                            fontWeight: AppType.bold,
                            color: palette.primary)),
                  ],
                ),
              ),
            ),
          ),
          _Field(
            label: 'Reason',
            child: ReasonChips(
              selected: _reason,
              customReason: _customReason,
              accent: meta.color,
              softAccent: meta.soft,
              onSelected: (r) => setState(() => _reason = r),
              onCustomChanged: (v) => setState(() => _customReason = v),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppPrimaryButton(
            label: 'Apply from ${formatFeeDate(_effectiveFrom)}',
            icon: Icons.refresh,
            busy: _busy,
            onPressed: _valid ? _save : null,
          ),
          if (!_valid) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_missing(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
          ],
        ],
      ),
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

  Widget _timeTile(AppPalette palette, String caption, ClockTime? value, Color accent,
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
                      fontSize: 15,
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

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label.toUpperCase(), style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          child,
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(hint!,
                style: TextStyle(
                    fontSize: AppType.sm, color: palette.textFaint, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

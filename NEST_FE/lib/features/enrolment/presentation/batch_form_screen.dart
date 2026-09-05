import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';

/// Create or edit a batch, including its weekly pattern and roster. Pops `true` when saved.
///
/// The schedule is set through a second call after the batch itself is saved: schedule slots are
/// a separate resource keyed by batch id, so there is nothing to attach them to until the batch
/// exists.
class BatchFormScreen extends ConsumerStatefulWidget {
  const BatchFormScreen({super.key, this.existing, this.initialType});

  final Batch? existing;

  /// Which kind of batch the add menu asked for. Ignored when editing - the type is fixed once
  /// the batch exists, since it decides whether the course's regular fee cycle applies.
  final BatchType? initialType;

  @override
  ConsumerState<BatchFormScreen> createState() => _BatchFormScreenState();
}

class _BatchFormScreenState extends ConsumerState<BatchFormScreen> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');

  late final BatchType _batchType =
      widget.existing?.batchType ?? widget.initialType ?? BatchType.regular;

  late String? _courseId = widget.existing?.courseId;
  late Set<Weekday> _days = {};
  ClockTime? _startTime;
  ClockTime? _endTime;
  late DateTime? _startDate = widget.existing?.startDate;
  late DateTime? _endDate = widget.existing?.endDate;
  late Set<String> _trainerIds = {
    for (final t in widget.existing?.trainers ?? const <BatchTrainer>[]) t.membershipId
  };
  Set<String> _studentIds = {};
  late bool _active = widget.existing?.isActive ?? true;

  /// Existing schedule and roster arrive asynchronously; until they do, the pickers must not
  /// present an empty selection as if the admin had cleared it.
  bool _prefilled = false;
  bool _busy = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadExisting();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final batchId = widget.existing!.id;
    try {
      final slots = await ref.read(schedulingApiProvider).currentSchedule(batchId);
      final members = await ref.read(enrolmentApiProvider).members(batchId);
      if (!mounted) return;
      setState(() {
        _days = slots.map((s) => Weekday.fromWire(s.dayOfWeek)).toSet();
        // Every slot of a batch shares one time; the first is representative. A batch whose
        // slots somehow differ would need a per-day editor, which the design doesn't have.
        if (slots.isNotEmpty) {
          _startTime = ClockTime.tryParse(slots.first.startTime);
          _endTime = ClockTime.tryParse(slots.first.endTime);
        }
        _studentIds = members.toSet();
        _prefilled = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _prefilled = true);
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

  bool get _datesValid {
    if (_startDate == null) return false;
    if (_batchType == BatchType.temporary) {
      return _endDate != null && !_endDate!.isBefore(_startDate!);
    }
    return true;
  }

  bool get _valid =>
      _nameController.text.trim().length > 1 &&
      _courseId != null &&
      _days.isNotEmpty &&
      _timeValid &&
      _datesValid &&
      _trainerIds.isNotEmpty &&
      _studentIds.isNotEmpty;

  String _missingRequirement() {
    if (_nameController.text.trim().length <= 1) return 'Enter a batch name to continue.';
    if (_courseId == null) return 'Pick the course this batch belongs to.';
    if (_days.isEmpty) return 'Select at least one day.';
    if (_startTime == null || _endTime == null) return 'Set the class start and end time.';
    if (!_timeValid) return 'The end time must be after the start time.';
    if (_startDate == null) return 'Pick the date this batch starts.';
    if (!_datesValid) return 'A temporary batch needs an end date on or after the start.';
    if (_trainerIds.isEmpty) return 'Select at least one instructor.';
    return 'Select at least one student.';
  }

  Future<void> _pickStartTime() async {
    final picked = await showAppTimePicker(
      context: context,
      title: 'Start time',
      initial: _startTime,
      accentColor: _accent(),
    );
    if (!mounted) return;
    setState(() => _startTime = picked);
    // Straight on to the end time - it is always the next thing needed, and the picker seeds
    // itself from the start so it opens somewhere sensible.
    if (picked != null) await _pickEndTime();
  }

  Future<void> _pickEndTime() async {
    final picked = await showAppTimePicker(
      context: context,
      title: 'End time',
      initial: _endTime,
      accentColor: context.palette.gold,
      minTime: _startTime,
    );
    if (!mounted) return;
    setState(() => _endTime = picked);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showAppCalendar(
      context: context,
      month: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      selectedDay: (isStart ? _startDate : _endDate)?.day,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // An end date now before the start is silently wrong rather than visibly wrong, so it's
        // cleared and asked for again instead.
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTrainers(Course course) async {
    final trainers = await ref.read(trainersForCourseProvider(course.id).future);
    if (!mounted) return;
    final chosen = await showPeoplePickerSheet(
      context: context,
      title: 'Select instructors',
      accentColor: course.category.meta(context.palette).color,
      searchHint: 'Search instructor',
      emptyLabel: 'No trainers are mapped to ${course.name} yet.',
      people: [
        for (final t in trainers)
          PickablePerson(id: t.membershipId, name: t.fullName, subtitle: t.username)
      ],
      initiallySelected: _trainerIds,
    );
    if (chosen != null && mounted) setState(() => _trainerIds = chosen);
  }

  Future<void> _pickStudents(Course course) async {
    final students = await ref.read(studentsForCourseProvider(course.id).future);
    if (!mounted) return;
    final chosen = await showPeoplePickerSheet(
      context: context,
      title: 'Select students',
      accentColor: course.category.meta(context.palette).color,
      searchHint: 'Search student',
      emptyLabel: 'No students are enrolled in ${course.name} yet.',
      people: [
        for (final s in students)
          PickablePerson(id: s.membershipId, name: s.fullName, subtitle: s.username)
      ],
      initiallySelected: _studentIds,
    );
    if (chosen != null && mounted) setState(() => _studentIds = chosen);
  }

  Color _accent() {
    final course = _selectedCourse();
    return course == null
        ? context.palette.primary
        : course.category.meta(context.palette).color;
  }

  Course? _selectedCourse() {
    final courses =
        ref.read(coursesForFeatureProvider(FeatureKeys.batchCreation)).valueOrNull ??
            const <Course>[];
    for (final c in courses) {
      if (c.id == _courseId) return c;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);

    final api = ref.read(enrolmentApiProvider);
    final scheduling = ref.read(schedulingApiProvider);

    try {
      final String batchId;
      if (_isEditing) {
        await api.updateBatch(
          widget.existing!.id,
          name: _nameController.text.trim(),
          description: widget.existing!.description,
          trainerMembershipIds: _trainerIds.toList(),
          startDate: _startDate,
          endDate: _batchType == BatchType.temporary ? _endDate : null,
          studentMembershipIds: _studentIds.toList(),
        );
        batchId = widget.existing!.id;
        if (_active != widget.existing!.isActive) {
          await api.setBatchStatus(batchId, _active ? 'ACTIVE' : 'INACTIVE');
        }
      } else {
        final created = await api.createBatch(
          courseId: _courseId!,
          name: _nameController.text.trim(),
          batchType: _batchType,
          trainerMembershipIds: _trainerIds.toList(),
          startDate: _startDate,
          endDate: _batchType == BatchType.temporary ? _endDate : null,
          studentMembershipIds: _studentIds.toList(),
        );
        batchId = created.id;
        if (!_active) await api.setBatchStatus(batchId, 'INACTIVE');
      }

      // One slot per selected day, all sharing the batch's single time window. Sent after the
      // batch exists because slots are keyed by batch id.
      await scheduling.setSchedule(
        batchId: batchId,
        effectiveFrom: _isoDate(_startDate!),
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

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.batchCreation));
    final course = _selectedCourse();
    final meta = (course?.category ?? CourseCategory.unknown).meta(palette);
    final typeAccent = _batchType == BatchType.temporary ? palette.gold : palette.primary;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isEditing ? 'Edit Batch' : 'Add Batch',
                style: TextStyle(
                    fontSize: 17, fontWeight: AppType.bold, color: palette.text)),
            Text(
              _isEditing
                  ? '${widget.existing!.name} · ${course?.name ?? ''}'
                  : 'Create a new ${_batchType.label.toLowerCase()} batch',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.page),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 5),
                decoration: BoxDecoration(
                  color: _batchType == BatchType.temporary
                      ? palette.goldSoft
                      : palette.primarySoft,
                  borderRadius: AppRadii.all(AppRadii.pill),
                  border: Border.all(color: typeAccent.withValues(alpha: 0.33)),
                ),
                child: Text(
                  _batchType.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: AppType.tiny,
                    fontWeight: AppType.heavy,
                    letterSpacing: 0.4,
                    color: typeAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4l),
            child: Text(e.toString().replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
          ),
        ),
        data: (courses) {
          // A deactivated course can't take a new batch, but the one this batch is already on
          // must stay listed or editing would silently blank the course field.
          final selectable = courses
              .where((c) => c.isActive || c.id == _courseId)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x5l),
            children: [
              if (_isEditing && !_prefilled)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: palette.surfaceHigh,
                    color: palette.primary,
                  ),
                ),
              _Field(
                label: 'Batch name',
                child: TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                      fontSize: AppType.xxl,
                      fontWeight: AppType.medium,
                      color: palette.text),
                  decoration: _decoration(palette, 'e.g. Batch A'),
                ),
              ),
              _Field(
                label: 'Course',
                hint: _isEditing
                    ? 'A batch stays on the course it was created for - its fees and history '
                        'are already scoped to it.'
                    : 'Only active courses can take on a new batch.',
                child: AttachedSelect<Course>(
                  label: 'Course',
                  options: selectable,
                  labelOf: (c) => c.name,
                  value: course,
                  placeholder: 'Select a course',
                  searchable: true,
                  searchHint: 'Search course',
                  // Changing it after the fact would re-scope fees and attendance already
                  // recorded against the original course.
                  locked: _isEditing,
                  onSelected: (c) => setState(() {
                    _courseId = c.id;
                    // Trainers and students are course-scoped, so a course change invalidates
                    // both selections rather than carrying across people who aren't on it.
                    _trainerIds = {};
                    _studentIds = {};
                  }),
                  optionBuilder: (context, option, _) {
                    final m = option.category.meta(palette);
                    final selected = option.id == _courseId;
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
                          child: Text(
                            option.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.xl,
                              fontWeight: selected ? AppType.bold : AppType.regular,
                              color: selected ? m.color : palette.text,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
                                child: Text(
                                  day.initial,
                                  style: TextStyle(
                                    fontSize: AppType.base,
                                    fontWeight: AppType.bold,
                                    color: _days.contains(day)
                                        ? palette.onGold
                                        : palette.textMuted,
                                  ),
                                ),
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
                      child: _TimeTile(
                        caption: 'Start',
                        value: _startTime?.label,
                        accent: meta.color,
                        onTap: _pickStartTime,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _TimeTile(
                        caption: 'End',
                        value: _endTime?.label,
                        accent: palette.gold,
                        onTap: _pickEndTime,
                      ),
                    ),
                  ],
                ),
              ),
              _Field(
                label: _batchType == BatchType.temporary
                    ? 'Start & end date'
                    : 'Start date',
                hint: _batchType == BatchType.temporary
                    ? 'Temporary batches run only between these two dates.'
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        value: _startDate,
                        placeholder: _batchType == BatchType.temporary
                            ? 'Start date'
                            : 'Select the date this batch starts',
                        accent: palette.gold,
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    if (_batchType == BatchType.temporary) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _DateTile(
                          value: _endDate,
                          placeholder: 'End date',
                          accent: palette.gold,
                          onTap: () => _pickDate(isStart: false),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_batchType == BatchType.temporary) _temporaryFeeNotice(palette),
              _Field(
                label: 'Instructor',
                hint: _trainerIds.isEmpty
                    ? 'Select at least one instructor. A batch can have more than one.'
                    : null,
                child: _PeopleTile(
                  icon: Icons.person_outline,
                  accent: meta.color,
                  emptyLabel: 'Select instructor(s) for this batch',
                  names: widget.existing?.trainers
                          .where((t) => _trainerIds.contains(t.membershipId))
                          .map((t) => t.name)
                          .toList() ??
                      const [],
                  count: _trainerIds.length,
                  seeds: _trainerIds.toList(),
                  onTap: course == null ? null : () => _pickTrainers(course),
                ),
              ),
              _Field(
                label: 'Students',
                hint: _studentIds.isEmpty ? 'Select at least one student.' : null,
                child: _PeopleTile(
                  icon: Icons.groups_outlined,
                  accent: meta.color,
                  emptyLabel: 'Select students for this batch',
                  names: const [],
                  count: _studentIds.length,
                  seeds: _studentIds.toList(),
                  countNoun: 'student',
                  onTap: course == null ? null : () => _pickStudents(course),
                ),
              ),
              _Field(
                label: 'Status',
                hint: 'Inactive batches stay in history but drop off attendance and '
                    'fee-collection lists.',
                child: AppSegmentedControl<bool>(
                  options: const [true, false],
                  labelOf: (a) => a ? 'Active' : 'Inactive',
                  isSelected: (a) => a == _active,
                  activeColorOf: (_, a) => a ? palette.paidManual : palette.surfaceHigh,
                  activeTextColorOf: (_, a) => a ? palette.onPrimary : palette.textMuted,
                  onTap: (a) => setState(() => _active = a),
                ),
              ),
              _Field(
                label: 'Capacity',
                hint: 'Counted automatically from the students selected above.',
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
                      Icon(Icons.groups_outlined, size: 15, color: meta.color),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          '${_studentIds.length} student'
                          '${_studentIds.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: AppType.xxl,
                            fontWeight: AppType.bold,
                            color: palette.text,
                          ),
                        ),
                      ),
                      Text('Auto',
                          style: TextStyle(
                              fontSize: AppType.xs,
                              fontWeight: AppType.medium,
                              color: palette.textFaint)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppPrimaryButton(
                label: _isEditing ? 'Save changes' : 'Create batch',
                icon: Icons.check,
                busy: _busy,
                onPressed: _valid ? _save : null,
              ),
              if (!_valid) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _missingRequirement(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Temporary batches deliberately skip the course's regular fee cycle - without saying so here,
  /// an admin would reasonably assume the course fee applies and only find out when nobody is
  /// billed.
  Widget _temporaryFeeNotice(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x4l),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: palette.goldSoft,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.gold.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 16, color: palette.gold),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No regular fees applied',
                      style: TextStyle(
                          fontSize: AppType.md,
                          fontWeight: AppType.bold,
                          color: palette.gold)),
                  const SizedBox(height: 3),
                  Text(
                    "Temporary batches skip the course's regular fee cycle. If this batch needs "
                    'its own charge, add it as an Other Fee.',
                    style: TextStyle(
                        fontSize: AppType.sm, color: palette.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(AppPalette palette, String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
            fontSize: AppType.lg, fontWeight: AppType.regular, color: palette.textFaint),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.xl),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.xl),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.xl),
          borderSide: BorderSide(color: palette.primary),
        ),
      );
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.caption,
    required this.value,
    required this.accent,
    required this.onTap,
  });

  final String caption;
  final String? value;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                Icon(Icons.schedule,
                    size: 15, color: value == null ? palette.textFaint : accent),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    value ?? 'Set time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.x3l,
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

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.value,
    required this.placeholder,
    required this.accent,
    required this.onTap,
  });

  final DateTime? value;
  final String placeholder;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
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
            Icon(Icons.calendar_today_outlined,
                size: 16, color: value == null ? palette.textFaint : accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                value == null ? placeholder : formatFeeDate(value!),
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
    );
  }
}

/// The instructor / student selector tile. Shows stacked avatars once people are chosen, which
/// reads faster than a comma list when there are several.
class _PeopleTile extends StatelessWidget {
  const _PeopleTile({
    required this.icon,
    required this.accent,
    required this.emptyLabel,
    required this.names,
    required this.count,
    required this.seeds,
    required this.onTap,
    this.countNoun,
  });

  final IconData icon;
  final Color accent;
  final String emptyLabel;

  /// Resolved names when known. Empty is fine - the count and avatars still convey the selection,
  /// and names aren't loaded just to render this tile.
  final List<String> names;
  final int count;
  final List<String> seeds;
  final String? countNoun;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasSelection = count > 0;

    final String label;
    if (!hasSelection) {
      label = emptyLabel;
    } else if (countNoun != null || names.isEmpty) {
      final noun = countNoun ?? 'selected';
      label = countNoun == null
          ? '$count $noun'
          : '$count $noun${count == 1 ? '' : 's'} selected';
    } else {
      label = names.join(', ');
    }

    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Pressable(
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
              if (hasSelection)
                SizedBox(
                  height: 28,
                  width: (seeds.length.clamp(1, 3) * 18) + 10,
                  child: Stack(
                    children: [
                      for (var i = 0; i < seeds.length && i < 3; i++)
                        Positioned(
                          left: i * 18.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: palette.surfaceRaised, width: 2),
                            ),
                            child: PersonAvatar(
                              name: i < names.length ? names[i] : '?',
                              seed: seeds[i],
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Icon(icon, size: 16, color: palette.textFaint),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: AppType.medium,
                    color: hasSelection ? palette.text : palette.textFaint,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                hasSelection ? 'Edit' : 'Select',
                style: TextStyle(
                  fontSize: AppType.base,
                  fontWeight: AppType.bold,
                  color: palette.primary,
                ),
              ),
            ],
          ),
        ),
      ),
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

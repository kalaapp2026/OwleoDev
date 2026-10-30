import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/app_text_field.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/app_top_bar.dart' show AppBarBackTile;
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/validation/validators.dart';
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
  late final _linkController = TextEditingController(text: widget.existing?.meetingLink ?? '');

  late final BatchType _batchType =
      widget.existing?.batchType ?? widget.initialType ?? BatchType.regular;

  /// Every course the batch covers; the first is its primary. A batch can span several - Basic,
  /// Intermediate and Advanced learners in one class.
  late List<String> _courseIds = [...?widget.existing?.courseIds];
  String? get _courseId => _courseIds.isEmpty ? null : _courseIds.first;
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
    _linkController.dispose();
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

  /// The link is optional, but one that is typed has to look like a web address.
  bool get _linkValid => Validators.url(label: 'meeting link', required: false)(_linkController.text) == null;

  /// What is sent: nothing for a blank box, and `https://` added when the link was pasted without it (the
  /// server only takes http or https links).
  String? get _linkForSave {
    final v = _linkController.text.trim();
    if (v.isEmpty) return null;
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(v) ? v : 'https://$v';
  }

  bool get _valid =>
      _linkValid &&
      _nameController.text.trim().length > 1 &&
      _courseId != null &&
      _days.isNotEmpty &&
      _timeValid &&
      _datesValid &&
      _trainerIds.isNotEmpty &&
      _studentIds.isNotEmpty;

  String _missingRequirement() {
    if (_nameController.text.trim().length <= 1) return 'Enter a batch name to continue.';
    if (!_linkValid) return 'The meeting link does not look like a web address.';
    if (_courseId == null) return 'Pick at least one course.';
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
      accentColor: context.palette.primary,
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
    // A batch cannot start in the past, and cannot end before it starts: earlier days are greyed out
    // in the calendar rather than rejected after the tap.
    final today = DateUtils.dateOnly(DateTime.now());
    final start = _startDate;
    final floor = isStart ? today : (start != null && start.isAfter(today) ? start : today);
    final current = isStart ? _startDate : _endDate;
    final usable = current != null && !current.isBefore(floor);
    final picked = await showAppCalendar(
      context: context,
      month: usable ? current : floor,
      selectedDay: usable ? current.day : null,
      earliestDay: floor,
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

  /// Trainers mapped to ANY of the selected courses, de-duplicated. A trainer of one course can take a
  /// class that also holds another course's students.
  Future<List<TrainerSummary>> _trainersForSelected(List<Course> courses) async {
    final lists = await Future.wait([
      for (final c in courses) ref.read(trainersForCourseProvider(c.id).future),
    ]);
    final byId = <String, TrainerSummary>{};
    for (final list in lists) {
      for (final t in list) {
        byId.putIfAbsent(t.membershipId, () => t);
      }
    }
    return byId.values.toList();
  }

  Future<void> _pickTrainers() async {
    final courses = _selectedCourses();
    if (courses.isEmpty) return;
    final trainers = await _trainersForSelected(courses);
    if (!mounted) return;
    final chosen = await showPeoplePickerSheet(
      context: context,
      title: 'Select instructors',
      accentColor: courses.first.category.meta(context.palette).color,
      searchHint: 'Search instructor',
      emptyLabel: courses.length == 1
          ? 'No trainers are mapped to ${courses.first.name} yet.'
          : 'No trainers are mapped to these courses yet.',
      people: [
        for (final t in trainers)
          PickablePerson(id: t.membershipId, name: t.fullName, subtitle: t.username)
      ],
      initiallySelected: _trainerIds,
    );
    if (chosen != null && mounted) setState(() => _trainerIds = chosen);
  }

  /// The students of every selected course, each tagged with the course(s) they are enrolled in so a
  /// mixed batch reads at a glance.
  Future<({List<StudentSummary> students, Map<String, List<String>> coursesOf})> _studentsForSelected(
      List<Course> courses) async {
    final lists = await Future.wait([
      for (final c in courses) ref.read(studentsForCourseProvider(c.id).future),
    ]);
    final byId = <String, StudentSummary>{};
    final coursesOf = <String, List<String>>{};
    for (var i = 0; i < courses.length; i++) {
      for (final s in lists[i]) {
        byId.putIfAbsent(s.membershipId, () => s);
        coursesOf.putIfAbsent(s.membershipId, () => []).add(courses[i].name);
      }
    }
    return (students: byId.values.toList(), coursesOf: coursesOf);
  }

  Future<void> _pickStudents() async {
    final courses = _selectedCourses();
    if (courses.isEmpty) return;
    final found = await _studentsForSelected(courses);
    if (!mounted) return;
    final multi = courses.length > 1;
    final chosen = await showPeoplePickerSheet(
      context: context,
      title: 'Select students',
      accentColor: courses.first.category.meta(context.palette).color,
      searchHint: 'Search student',
      emptyLabel: multi
          ? 'No students are enrolled in these courses yet.'
          : 'No students are enrolled in ${courses.first.name} yet.',
      people: [
        for (final s in found.students)
          PickablePerson(
            id: s.membershipId,
            name: s.fullName,
            subtitle: multi
                ? '${s.username} · ${found.coursesOf[s.membershipId]?.join(', ') ?? ''}'
                : s.username,
          )
      ],
      initiallySelected: _studentIds,
    );
    if (chosen != null && mounted) setState(() => _studentIds = chosen);
  }

  /// The selected courses the editor can list people for, in selection order. A course they hold no
  /// Batch creation on is not in their picker list, so it contributes no people here.
  List<Course> _selectedCourses() {
    final all = ref.read(coursesForFeatureProvider(FeatureKeys.batchCreation)).valueOrNull ??
        const <Course>[];
    return [
      for (final id in _courseIds)
        for (final c in all)
          if (c.id == id) c
    ];
  }

  Course? _selectedCourse() {
    final selected = _selectedCourses();
    return selected.isNotEmpty && selected.first.id == _courseId ? selected.first : null;
  }

  String _courseNameOf(String id, List<Course> courses) {
    for (final c in courses) {
      if (c.id == id) return c.name;
    }
    for (final c in widget.existing?.courses ?? const <BatchCourse>[]) {
      if (c.id == id) return c.name;
    }
    return 'Course';
  }

  Color _courseColorOf(String id, List<Course> courses, AppPalette palette) {
    for (final c in courses) {
      if (c.id == id) return c.category.meta(palette).color;
    }
    return palette.textMuted;
  }

  Future<void> _pickCourses(List<Course> selectable) async {
    final picked = await showAppMultiSelectSheet<Course>(
      context: context,
      title: 'Courses in this batch',
      options: selectable,
      labelOf: (c) => c.name,
      initialSelection: selectable.where((c) => _courseIds.contains(c.id)).toList(),
    );
    if (picked == null || !mounted) return;
    final pickedIds = picked.map((c) => c.id).toSet();
    final selectableIds = selectable.map((c) => c.id).toSet();
    setState(() {
      // Courses already on the batch keep their place, so the primary does not shuffle; courses the
      // editor cannot manage stay put; newly picked ones follow in the order they were picked.
      _courseIds = [
        for (final id in _courseIds)
          if (pickedIds.contains(id) || !selectableIds.contains(id)) id,
        for (final c in picked)
          if (!_courseIds.contains(c.id)) c.id,
      ];
    });
    await _pruneToSelectedCourses();
  }

  /// People are course-scoped, so changing the courses drops the instructors and students who are not
  /// on any of the selected ones rather than carrying them across.
  Future<void> _pruneToSelectedCourses() async {
    final courses = _selectedCourses();
    if (courses.isEmpty) {
      setState(() {
        _trainerIds = {};
        _studentIds = {};
      });
      return;
    }
    try {
      final trainers = await _trainersForSelected(courses);
      final found = await _studentsForSelected(courses);
      if (!mounted) return;
      final trainerIds = trainers.map((t) => t.membershipId).toSet();
      final studentIds = found.students.map((s) => s.membershipId).toSet();
      setState(() {
        _trainerIds = _trainerIds.where(trainerIds.contains).toSet();
        _studentIds = _studentIds.where(studentIds.contains).toSet();
      });
    } catch (e) {
      _showError(e);
    }
  }

  String _courseNamesLabel(List<Course> courses) =>
      _courseIds.map((id) => _courseNameOf(id, courses)).join(', ');

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
          courseIds: _courseIds,
          description: widget.existing!.description,
          trainerMembershipIds: _trainerIds.toList(),
          startDate: _startDate,
          endDate: _batchType == BatchType.temporary ? _endDate : null,
          studentMembershipIds: _studentIds.toList(),
          meetingLink: _linkForSave,
        );
        batchId = widget.existing!.id;
        if (_active != widget.existing!.isActive) {
          await api.setBatchStatus(batchId, _active ? 'ACTIVE' : 'INACTIVE');
        }
      } else {
        final created = await api.createBatch(
          courseIds: _courseIds,
          name: _nameController.text.trim(),
          batchType: _batchType,
          trainerMembershipIds: _trainerIds.toList(),
          startDate: _startDate,
          endDate: _batchType == BatchType.temporary ? _endDate : null,
          studentMembershipIds: _studentIds.toList(),
          meetingLink: _linkForSave,
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
        leading: AppBarBackTile(onTap: () => Navigator.of(context).pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isEditing ? 'Edit Batch' : 'Add Batch',
                style: TextStyle(
                    fontSize: 17, fontWeight: AppType.bold, color: palette.text)),
            Text(
              _isEditing
                  ? '${widget.existing!.name} · ${_courseNamesLabel(ref.watch(coursesForFeatureProvider(FeatureKeys.batchCreation)).valueOrNull ?? const <Course>[])}'
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
              .where((c) => c.isActive || _courseIds.contains(c.id))
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
                label: 'Courses',
                hint: _isEditing
                    ? 'Add a course to take its students in, or remove one once none of its students are in '
                        'the batch. A course you have no Batch creation on stays as it is.'
                    : 'Pick every course whose students learn together in this batch. Each student keeps their '
                        "own course's fee.",
                child: _CoursesTile(
                  chips: [
                    for (final id in _courseIds)
                      _CourseChip(
                        name: _courseNameOf(id, courses),
                        color: _courseColorOf(id, courses, palette),
                        locked: !selectable.any((c) => c.id == id),
                      ),
                  ],
                  onTap: () => _pickCourses(selectable),
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
                        accent: palette.primary,
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
                        accent: palette.primary,
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
                label: 'Online class link',
                hint: 'Optional. Paste the Google Meet, Zoom or Teams link; students and instructors get a Join '
                    'button on each class in their schedule.',
                child: AppTextField(
                  controller: _linkController,
                  hint: 'https://meet.google.com/abc-defg-hij',
                  icon: Icons.videocam_outlined,
                  preset: FieldPreset.url(label: 'meeting link', required: false),
                  showErrors: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
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
                  onTap: _selectedCourses().isEmpty ? null : _pickTrainers,
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
                  onTap: _selectedCourses().isEmpty ? null : _pickStudents,
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

/// One course on the batch. [locked] marks a course the editor cannot change - they hold no Batch
/// creation on it - so it stays on the batch whatever they do here.
class _CourseChip {
  const _CourseChip({required this.name, required this.color, required this.locked});

  final String name;
  final Color color;
  final bool locked;
}

/// The batch's courses as chips, tapping which opens the multi-select.
class _CoursesTile extends StatelessWidget {
  const _CoursesTile({required this.chips, required this.onTap});

  final List<_CourseChip> chips;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined,
                size: 16, color: chips.isEmpty ? palette.textMuted : palette.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: chips.isEmpty
                  ? Text('Select course(s)',
                      style: TextStyle(fontSize: AppType.lg, color: palette.textMuted))
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [for (final chip in chips) _chip(palette, chip)],
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              chips.isEmpty ? 'Select' : 'Edit',
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

  Widget _chip(AppPalette palette, _CourseChip chip) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: 0.14),
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(color: chip.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chip.locked) ...[
            Icon(Icons.lock_outline, size: 11, color: chip.color),
            const SizedBox(width: 4),
          ],
          Text(
            chip.name,
            style: TextStyle(
              fontSize: AppType.smd,
              fontWeight: AppType.semi,
              color: chip.color,
            ),
          ),
        ],
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

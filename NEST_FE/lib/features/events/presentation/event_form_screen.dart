import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/events/presentation/event_common.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;

/// What the form resolves to when it closes, so the screen that opened it knows whether to
/// refresh, or - after a delete - to close itself too.
const eventFormSaved = 'saved';
const eventFormDeleted = 'deleted';

/// Opens the event form. Resolves to [eventFormSaved] or [eventFormDeleted], or null if the user
/// backed out. Pass [existing] to edit, or an event with an empty id to create from a copy.
Future<String?> openEventForm(BuildContext context, {Event? existing}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => EventFormScreen(existing: existing)));
}

const _audienceOptions = [
  ('ALL_STUDENTS', 'All students', Icons.groups_outlined),
  ('ALL_TRAINERS', 'All trainers', Icons.badge_outlined),
  ('BY_COURSE', 'By course', Icons.auto_stories_outlined),
  ('BY_BATCH', 'By batch', Icons.grid_view_outlined),
  ('INDIVIDUALS', 'Individuals', Icons.person_outline),
];

class _BatchOption {
  const _BatchOption(this.batch, this.courseName);
  final Batch batch;
  final String courseName;
  String get label => '${batch.name} · $courseName';
}

String _combine(DateTime date, ClockTime? time) {
  final t = time ?? const ClockTime(0, 0);
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}T${t.wire}:00';
}

/// Create AND edit - pass [existing] to edit. Replaces the old create-only `event_create_screen.dart`.
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.existing});
  final Event? existing;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _locationController = TextEditingController(text: widget.existing?.location);
  late final _mapsController = TextEditingController(text: widget.existing?.venueMapsUrl);

  late String _type = widget.existing?.type ?? 'PROGRAMME';
  late String _visibility = widget.existing?.visibility ?? 'INHOUSE';
  late String _status = widget.existing?.status == 'DRAFT' ? 'DRAFT' : 'PUBLISHED';
  late String _audienceType = widget.existing?.audienceType ?? 'ALL_STUDENTS';
  late Set<String> _courseIds = {...?widget.existing?.courseIds};
  late Set<String> _batchIds = {...?widget.existing?.batchIds};
  late Set<String> _individualIds = {...?widget.existing?.individualIds};

  late DateTime _date = _parseDatePart(widget.existing?.eventDate) ?? DateTime.now().add(const Duration(days: 1));
  late ClockTime? _startTime = _parseTimePart(widget.existing?.eventDate);
  bool _isMultiDay = false;
  DateTime? _endDate;
  ClockTime? _endTime;
  DateTime? _interestDeadline;

  bool _isSaving = false;
  List<_BatchOption>? _batchOptions;
  List<PickablePerson>? _peopleOptions;
  bool _loadingAudienceOptions = false;

  /// A duplicate arrives as an event with no id: it seeds the fields but is created, not updated.
  bool get _isEditing => widget.existing != null && widget.existing!.id.isNotEmpty;

  late bool _showMapsLink = (widget.existing?.venueMapsUrl ?? '').isNotEmpty;

  static DateTime? _parseDatePart(String? iso) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static ClockTime? _parseTimePart(String? iso) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null || (d.hour == 0 && d.minute == 0)) return null;
    return ClockTime(d.hour, d.minute);
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing?.endDate != null) {
      final end = _parseDatePart(existing!.endDate);
      _endTime = _parseTimePart(existing.endDate);
      if (end != null && (end.year != _date.year || end.month != _date.month || end.day != _date.day)) {
        _isMultiDay = true;
        _endDate = end;
      }
    }
    if (existing?.interestDeadline != null) {
      _interestDeadline = DateTime.tryParse(existing!.interestDeadline!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _mapsController.dispose();
    super.dispose();
  }

  Future<void> _loadAudienceOptions(List<Course> courses) async {
    if (_batchOptions != null || _loadingAudienceOptions) return;
    setState(() => _loadingAudienceOptions = true);
    try {
      final api = ref.read(enrolmentApiProvider);
      final batchLists = await Future.wait(courses.map((c) => api.batchesForCourse(c.id)));
      final batches = <_BatchOption>[];
      for (var i = 0; i < courses.length; i++) {
        for (final b in batchLists[i]) {
          batches.add(_BatchOption(b, courses[i].name));
        }
      }
      final studentLists = await Future.wait(courses.map((c) => api.studentsForCourse(c.id)));
      final trainerLists = await Future.wait(courses.map((c) => api.trainersForCourse(c.id)));
      final peopleById = <String, PickablePerson>{};
      for (final list in studentLists) {
        for (final s in list) {
          peopleById[s.membershipId] = PickablePerson(id: s.membershipId, name: s.fullName, subtitle: 'Student');
        }
      }
      for (final list in trainerLists) {
        for (final t in list) {
          peopleById[t.membershipId] = PickablePerson(id: t.membershipId, name: t.fullName, subtitle: 'Trainer');
        }
      }
      if (mounted) {
        setState(() {
          _batchOptions = batches;
          _peopleOptions = peopleById.values.toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingAudienceOptions = false);
    }
  }

  Future<void> _pickDate({required bool isEnd}) async {
    final base = isEnd ? (_endDate ?? _date) : _date;
    final picked = await showAppCalendar(context: context, month: DateTime(base.year, base.month), selectedDay: base.day);
    if (picked == null) return;
    setState(() => isEnd ? _endDate = picked : _date = picked);
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final picked = await showAppTimePicker(
      context: context,
      title: isEnd ? 'End time' : 'Start time',
      initial: isEnd ? _endTime : _startTime,
      accentColor: isEnd ? context.palette.gold : null,
      // The end of a one-day event must come after its start; a multi-day event ends on another
      // day, so the start time says nothing about it.
      minTime: isEnd && !_isMultiDay ? _startTime : null,
    );
    if (!mounted) return;
    setState(() => isEnd ? _endTime = picked : _startTime = picked);
    // Setting a start leads straight into the end, as the prototype does.
    if (!isEnd && picked != null && _endTime == null) await _pickTime(isEnd: true);
  }

  Future<void> _deleteEvent() async {
    final event = widget.existing;
    if (event == null || !await confirmAndDeleteEvent(context, ref, event)) return;
    if (mounted) Navigator.of(context).pop(eventFormDeleted);
  }

  Future<void> _pickInterestDeadline() async {
    final base = _interestDeadline ?? _date;
    final picked = await showAppCalendar(context: context, month: DateTime(base.year, base.month), selectedDay: _interestDeadline?.day);
    setState(() => _interestDeadline = picked);
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty && _locationController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    final eventDate = _combine(_date, _startTime);
    final hasEnd = _isMultiDay || _endTime != null;
    final endDate = hasEnd ? _combine(_isMultiDay ? (_endDate ?? _date) : _date, _endTime) : null;
    final interestDeadline = _interestDeadline == null
        ? null
        : '${_interestDeadline!.year.toString().padLeft(4, '0')}-${_interestDeadline!.month.toString().padLeft(2, '0')}-${_interestDeadline!.day.toString().padLeft(2, '0')}';
    try {
      if (_isEditing) {
        await ref.read(eventsApiProvider).update(
              id: widget.existing!.id,
              type: _type,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              eventDate: eventDate,
              endDate: endDate,
              location: _locationController.text.trim(),
              venueMapsUrl: _mapsController.text.trim().isEmpty ? null : _mapsController.text.trim(),
              visibility: _visibility,
              interestDeadline: interestDeadline,
              audienceType: _audienceType,
              courseIds: _courseIds,
              batchIds: _batchIds,
              individualIds: _individualIds,
            );
      } else {
        await ref.read(eventsApiProvider).create(
              type: _type,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              eventDate: eventDate,
              endDate: endDate,
              location: _locationController.text.trim(),
              venueMapsUrl: _mapsController.text.trim().isEmpty ? null : _mapsController.text.trim(),
              visibility: _visibility,
              interestDeadline: interestDeadline,
              status: _status,
              audienceType: _audienceType,
              courseIds: _courseIds,
              batchIds: _batchIds,
              individualIds: _individualIds,
            );
      }
      if (mounted) {
        AppNotice.success(context, _isEditing ? 'Event updated.' : 'Event created.');
        Navigator.of(context).pop(eventFormSaved);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.eventManagement));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: _isEditing ? 'Edit Event' : 'Add Event'),
            Expanded(
              child: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          _label('Event title'),
          _textField(_titleController, 'e.g. Annual Day 2026'),
          const SizedBox(height: AppSpacing.xxl),
          _label('Category'),
          AppSegmentedControl<String>(
            options: const ['PROGRAMME', 'LOOKING_FOR_ARTIST'],
            labelOf: (v) => v == 'PROGRAMME' ? 'Programme' : 'Looking for Artist',
            isSelected: (v) => v == _type,
            onTap: (v) => setState(() => _type = v),
            // Looking for Artist is not open yet. An existing event that already uses it keeps it
            // selected (and saves unchanged); nothing new can pick it.
            isEnabled: (v) => v == 'PROGRAMME',
            hintOf: (v) => v == 'PROGRAMME' ? null : 'Coming soon',
          ),
          const SizedBox(height: AppSpacing.xxl),
          _label('Event type'),
          AppSegmentedControl<String>(
            options: const ['INHOUSE', 'PUBLIC'],
            labelOf: (v) => v == 'INHOUSE' ? 'In-house' : 'Public',
            isSelected: (v) => v == _visibility,
            onTap: (v) => setState(() => _visibility = v),
            // Public events (and their auto-published Social post) are not open yet - same rule as
            // Category above.
            isEnabled: (v) => v == 'INHOUSE',
            hintOf: (v) => v == 'INHOUSE' ? null : 'Coming soon',
          ),
          if (_visibility == 'PUBLIC')
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Also auto-publishes a Social post from your academy\'s profile once Published.',
                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
            ),
          const SizedBox(height: AppSpacing.xxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Description'),
              Text('${_descriptionController.text.length}/200', style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
            ],
          ),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: palette.text),
            decoration: _decoration("What's this event about?"),
          ),
          const SizedBox(height: AppSpacing.md),
          _label('Venue'),
          _textField(_locationController, 'e.g. Academy Auditorium', icon: Icons.place_outlined),
          const SizedBox(height: AppSpacing.md),
          // The map link is optional, so it stays out of the way until asked for - and clearing
          // it with the X puts it away again.
          if (_showMapsLink)
            _textField(
              _mapsController,
              'Paste Google Maps link',
              icon: Icons.link,
              onClear: () => setState(() {
                _mapsController.clear();
                _showMapsLink = false;
              }),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _showMapsLink = true),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.link, size: 13, color: palette.primary),
                const SizedBox(width: 6),
                Text('Add Google Maps link (optional)',
                    style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.primary)),
              ]),
            ),
          const SizedBox(height: AppSpacing.xxl),
          _label('Date'),
          _pickerRow(icon: Icons.calendar_today_outlined, label: formatFeeDate(_date), onTap: () => _pickDate(isEnd: false)),
          const SizedBox(height: AppSpacing.md),
          _checkboxRow('This is a multi-day event', _isMultiDay, (v) => setState(() => _isMultiDay = v)),
          if (_isMultiDay) ...[
            const SizedBox(height: AppSpacing.md),
            _pickerRow(
              icon: Icons.calendar_today_outlined,
              label: _endDate == null ? 'Select end date' : formatFeeDate(_endDate!),
              onTap: () => _pickDate(isEnd: true),
              accent: palette.gold,
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          _label('Time (optional)'),
          Row(
            children: [
              Expanded(child: _pickerRow(icon: Icons.access_time, label: _startTime?.label ?? 'Set start', onTap: () => _pickTime(isEnd: false))),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: _pickerRow(
                      icon: Icons.access_time, label: _endTime?.label ?? 'Set end', onTap: () => _pickTime(isEnd: true), accent: palette.gold)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          _label('Who is this for?'),
          coursesAsync.when(
            data: (courses) => _audiencePicker(courses),
            loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            error: (e, _) => Text('Could not load courses.', style: TextStyle(color: palette.notPaid)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Interest deadline (optional)'),
              if (_interestDeadline != null)
                TextButton(onPressed: () => setState(() => _interestDeadline = null), child: const Text('Clear')),
            ],
          ),
          _pickerRow(
            icon: Icons.hourglass_bottom,
            label: _interestDeadline == null ? 'No deadline - open until the event' : formatFeeDate(_interestDeadline!),
            onTap: _pickInterestDeadline,
            accent: palette.gold,
          ),
          const SizedBox(height: AppSpacing.xxl),
          _label('Status'),
          AppSegmentedControl<String>(
            options: const ['PUBLISHED', 'DRAFT'],
            labelOf: (v) => v == 'PUBLISHED' ? 'Published' : 'Draft',
            isSelected: (v) => v == _status,
            onTap: _isEditing ? (_) {} : (v) => setState(() => _status = v),
          ),
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Use Cancel/Restore from the event list to change status once created.',
                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
            ),
        ],
      ),
            ),
            // Pinned, so Save is always one tap away however long the form has grown.
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.x3l),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppPrimaryButton(
                    label: _isEditing ? 'Save changes' : 'Create event',
                    icon: Icons.check,
                    busy: _isSaving,
                    onPressed: _canSave ? _submit : null,
                  ),
                  if (_isEditing)
                    TextButton(
                      onPressed: _isSaving ? null : _deleteEvent,
                      child: Text('Delete event', style: TextStyle(color: palette.notPaid, fontWeight: AppType.semi)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audiencePicker(List<Course> courses) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (value, label, icon) in _audienceOptions) ...[
          _audienceOptionRow(value, label, icon),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_audienceType == 'BY_COURSE')
          _pickerRow(
            icon: Icons.auto_stories_outlined,
            label: _courseIds.isEmpty ? 'Select courses' : '${_courseIds.length} course${_courseIds.length == 1 ? '' : 's'} selected',
            onTap: () async {
              final picked = await showAppMultiSelectSheet<Course>(
                context: context,
                title: 'Select courses',
                options: courses,
                labelOf: (c) => c.name,
                initialSelection: courses.where((c) => _courseIds.contains(c.id)).toList(),
              );
              if (picked != null) setState(() => _courseIds = picked.map((c) => c.id).toSet());
            },
          ),
        if (_audienceType == 'BY_BATCH')
          _pickerRow(
            icon: Icons.grid_view_outlined,
            label: _loadingAudienceOptions
                ? 'Loading batches…'
                : (_batchIds.isEmpty ? 'Select batches' : '${_batchIds.length} batch${_batchIds.length == 1 ? '' : 'es'} selected'),
            onTap: () async {
              await _loadAudienceOptions(courses);
              final options = _batchOptions ?? [];
              if (!mounted) return;
              final picked = await showAppMultiSelectSheet<_BatchOption>(
                context: context,
                title: 'Select batches',
                options: options,
                labelOf: (o) => o.label,
                initialSelection: options.where((o) => _batchIds.contains(o.batch.id)).toList(),
              );
              if (picked != null) setState(() => _batchIds = picked.map((o) => o.batch.id).toSet());
            },
          ),
        if (_audienceType == 'INDIVIDUALS')
          _pickerRow(
            icon: Icons.person_outline,
            label: _loadingAudienceOptions
                ? 'Loading people…'
                : (_individualIds.isEmpty ? 'Select individuals' : '${_individualIds.length} selected'),
            accent: palette.violet,
            onTap: () async {
              await _loadAudienceOptions(courses);
              final people = _peopleOptions ?? [];
              if (!mounted) return;
              final picked = await showPeoplePickerSheet(
                context: context,
                title: 'Select individuals',
                people: people,
                initiallySelected: _individualIds,
                accentColor: palette.violet,
                searchHint: 'Search student or trainer',
              );
              if (picked != null) setState(() => _individualIds = picked);
            },
          ),
      ],
    );
  }

  Widget _audienceOptionRow(String value, String label, IconData icon) {
    final palette = context.palette;
    final selected = _audienceType == value;
    final color = value == 'ALL_STUDENTS'
        ? palette.gold
        : value == 'ALL_TRAINERS'
            ? palette.gateway
            : value == 'INDIVIDUALS'
                ? palette.violet
                : palette.primary;
    return InkWell(
      onTap: () => setState(() => _audienceType = value),
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: selected ? color : palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? color : palette.textMuted),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: TextStyle(fontSize: AppType.xl, fontWeight: selected ? AppType.semi : AppType.regular, color: selected ? palette.text : palette.textMuted))),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? color : Colors.transparent,
                border: Border.all(color: selected ? color : palette.border, width: 1.5),
              ),
              child: selected ? const Icon(Icons.check, size: 11, color: Colors.black) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerRow({required IconData icon, required String label, required VoidCallback onTap, Color? accent}) {
    final palette = context.palette;
    final color = accent ?? palette.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: TextStyle(fontSize: AppType.xl, color: palette.text))),
            Icon(Icons.chevron_right, size: 16, color: palette.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged) {
    final palette = context.palette;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), activeColor: palette.primary),
          Text(label, style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text,
            style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: context.palette.textMuted, letterSpacing: 0.5)),
      );

  Widget _textField(TextEditingController controller, String hint, {IconData? icon, VoidCallback? onClear}) => TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: context.palette.text),
        decoration: _decoration(hint).copyWith(
          prefixIcon: icon == null ? null : Icon(icon, size: 16, color: context.palette.gold),
          suffixIcon: onClear == null ? null : IconButton(icon: Icon(Icons.close, size: 14, color: context.palette.textFaint), onPressed: onClear),
        ),
      );

  InputDecoration _decoration(String hint) {
    final palette = context.palette;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: palette.textFaint),
      filled: true,
      fillColor: palette.surfaceRaised,
      counterText: '',
      border: OutlineInputBorder(borderRadius: AppRadii.all(AppRadii.xl), borderSide: BorderSide(color: palette.border)),
      enabledBorder: OutlineInputBorder(borderRadius: AppRadii.all(AppRadii.xl), borderSide: BorderSide(color: palette.border)),
      focusedBorder: OutlineInputBorder(borderRadius: AppRadii.all(AppRadii.xl), borderSide: BorderSide(color: palette.primary)),
    );
  }
}

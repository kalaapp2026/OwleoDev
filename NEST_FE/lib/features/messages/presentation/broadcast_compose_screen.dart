import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';

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

/// Compose a broadcast to a resolved audience within the active academy. The audience picker is
/// the same shape as Event Creation's - same five types, same course/batch/people pickers -
/// since a broadcast's "who does this reach" question is identical to an event's.
class BroadcastComposeScreen extends ConsumerStatefulWidget {
  const BroadcastComposeScreen({super.key});

  @override
  ConsumerState<BroadcastComposeScreen> createState() => _BroadcastComposeScreenState();
}

class _BroadcastComposeScreenState extends ConsumerState<BroadcastComposeScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _audienceType = 'ALL_STUDENTS';
  Set<String> _courseIds = {};
  Set<String> _batchIds = {};
  Set<String> _individualIds = {};

  List<_BatchOption>? _batchOptions;
  List<PickablePerson>? _peopleOptions;
  bool _loadingAudienceOptions = false;
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _titleController.text.trim().isNotEmpty &&
      _bodyController.text.trim().isNotEmpty &&
      (_audienceType != 'BY_COURSE' || _courseIds.isNotEmpty) &&
      (_audienceType != 'BY_BATCH' || _batchIds.isNotEmpty) &&
      (_audienceType != 'INDIVIDUALS' || _individualIds.isNotEmpty);

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

  Future<void> _send() async {
    if (!_canSend || _isSending) return;
    setState(() => _isSending = true);
    try {
      final broadcast = await ref.read(messagesApiProvider).create(
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            audienceType: _audienceType,
            courseIds: _courseIds,
            batchIds: _batchIds,
            individualIds: _individualIds,
          );
      if (!mounted) return;
      ref.invalidate(sentBroadcastsProvider);
      AppNotice.success(context, 'Sent to ${broadcast.recipientCount} ${broadcast.recipientCount == 1 ? 'person' : 'people'}.');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coursesAsync = ref.watch(allCoursesProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('New Message')),
      body: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load courses.', style: TextStyle(color: palette.textMuted))),
        data: (courses) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.x6l),
          children: [
            _label('Title'),
            const SizedBox(height: AppSpacing.sm),
            _textField(_titleController, 'e.g. Recital rescheduled'),
            const SizedBox(height: AppSpacing.xl),
            _label('Message'),
            const SizedBox(height: AppSpacing.sm),
            _textField(_bodyController, 'What do you want to tell them?', maxLines: 5),
            const SizedBox(height: AppSpacing.x4l),
            _label('Audience'),
            const SizedBox(height: AppSpacing.sm),
            _audiencePicker(courses),
            const SizedBox(height: AppSpacing.x4l),
            FilledButton(
              onPressed: _canSend && !_isSending ? _send : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: palette.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
              ),
              child: _isSending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: context.palette.textMuted));

  Widget _textField(TextEditingController controller, String hint, {int maxLines = 1}) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.lg), borderSide: BorderSide(color: palette.borderSoft)),
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
            label: _loadingAudienceOptions ? 'Loading people…' : (_individualIds.isEmpty ? 'Select individuals' : '${_individualIds.length} selected'),
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
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: selected ? color : palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? color : palette.textMuted),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: AppType.xl, fontWeight: selected ? AppType.semi : AppType.regular, color: selected ? palette.text : palette.textMuted)),
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: color),
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
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.xl),
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
}

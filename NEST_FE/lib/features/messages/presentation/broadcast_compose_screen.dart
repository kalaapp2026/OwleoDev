import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';

const _maxBodyLength = 500;

const _audienceOptions = [
  ('ALL_STUDENTS', 'All students'),
  ('ALL_TRAINERS', 'All trainers'),
  ('EVERYONE', 'Everyone'),
  ('BY_COURSE', 'By course'),
  ('BY_BATCH', 'By batch'),
  ('INDIVIDUALS', 'Individuals'),
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
///
/// The recipient count is asked of the server rather than worked out here, so it is exactly the
/// number the send will reach (revoked members and other academies' ids already excluded).
class BroadcastComposeScreen extends ConsumerStatefulWidget {
  const BroadcastComposeScreen({super.key});

  @override
  ConsumerState<BroadcastComposeScreen> createState() => _BroadcastComposeScreenState();
}

class _BroadcastComposeScreenState extends ConsumerState<BroadcastComposeScreen> {
  final _bodyController = TextEditingController();

  String _audienceType = 'ALL_STUDENTS';
  Set<String> _courseIds = {};
  Set<String> _batchIds = {};
  Set<String> _individualIds = {};

  List<_BatchOption>? _batchOptions;
  List<PickablePerson>? _peopleOptions;
  bool _loadingAudienceOptions = false;
  bool _isSending = false;

  int? _recipientCount;
  int _countRequest = 0;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  bool get _hasAudience => switch (_audienceType) {
        'BY_COURSE' => _courseIds.isNotEmpty,
        'BY_BATCH' => _batchIds.isNotEmpty,
        'INDIVIDUALS' => _individualIds.isNotEmpty,
        _ => true,
      };

  bool get _canSend =>
      _bodyController.text.trim().isNotEmpty && _hasAudience && (_recipientCount ?? 0) > 0 && !_isSending;

  /// Re-asks the server how many people the current audience reaches. Only the latest answer is
  /// kept, so a slow reply for an audience the user has already moved off cannot overwrite it.
  Future<void> _refreshCount() async {
    final request = ++_countRequest;
    if (!_hasAudience) {
      setState(() => _recipientCount = 0);
      return;
    }
    try {
      final count = await ref.read(messagesApiProvider).previewRecipientCount(
            audienceType: _audienceType,
            courseIds: _courseIds,
            batchIds: _batchIds,
            individualIds: _individualIds,
          );
      if (mounted && request == _countRequest) setState(() => _recipientCount = count);
    } on ApiException {
      if (mounted && request == _countRequest) setState(() => _recipientCount = null);
    }
  }

  void _audienceChanged() {
    setState(() => _recipientCount = null);
    _refreshCount();
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

  Future<void> _send() async {
    if (!_canSend) return;
    final count = _recipientCount ?? 0;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Send broadcast?',
      message: 'This message will be sent to $count ${count == 1 ? 'person' : 'people'}. This can\'t be undone.',
      confirmLabel: 'Send',
      cancelLabel: 'Cancel',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSending = true);
    try {
      final broadcast = await ref.read(messagesApiProvider).create(
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
      body: SafeArea(
        child: Column(
          children: [
            const AppTopBar(title: 'New Broadcast'),
            Expanded(
              child: coursesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load courses.', style: TextStyle(color: palette.textMuted))),
                data: (courses) => ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x6l),
                  children: [
                    _label('Send to'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [for (final (value, label) in _audienceOptions) _audienceChip(value, label)],
                    ),
                    ..._audiencePickers(courses),
                    const SizedBox(height: AppSpacing.xxl),
                    _recipientBanner(),
                    const SizedBox(height: AppSpacing.xxl),
                    _label('Message'),
                    const SizedBox(height: AppSpacing.sm),
                    _messageField(),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.x3l),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
              child: FilledButton.icon(
                onPressed: _canSend ? _send : null,
                icon: _isSending
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: palette.onGold))
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Send broadcast'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: palette.gold,
                  foregroundColor: palette.onGold,
                  disabledBackgroundColor: palette.surfaceHigh,
                  disabledForegroundColor: palette.textFaint,
                  textStyle: const TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.xl)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text.toUpperCase(),
      style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, letterSpacing: 0.6, color: context.palette.textMuted));

  Widget _audienceChip(String value, String label) {
    final palette = context.palette;
    final selected = _audienceType == value;
    return GestureDetector(
      onTap: () {
        if (_audienceType == value) return;
        setState(() => _audienceType = value);
        _audienceChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.goldSoft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: selected ? palette.gold : palette.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: AppType.base,
                fontWeight: selected ? AppType.bold : AppType.regular,
                color: selected ? palette.gold : palette.textMuted)),
      ),
    );
  }

  List<Widget> _audiencePickers(List<Course> courses) {
    final palette = context.palette;
    return [
      if (_audienceType == 'BY_COURSE') ...[
        const SizedBox(height: AppSpacing.xxl),
        _label('Courses'),
        const SizedBox(height: AppSpacing.sm),
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
            if (picked != null) {
              setState(() => _courseIds = picked.map((c) => c.id).toSet());
              _audienceChanged();
            }
          },
        ),
      ],
      if (_audienceType == 'BY_BATCH') ...[
        const SizedBox(height: AppSpacing.xxl),
        _label('Batches'),
        const SizedBox(height: AppSpacing.sm),
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
            if (picked != null) {
              setState(() => _batchIds = picked.map((o) => o.batch.id).toSet());
              _audienceChanged();
            }
          },
        ),
      ],
      if (_audienceType == 'INDIVIDUALS') ...[
        const SizedBox(height: AppSpacing.xxl),
        _label('Students & trainers'),
        const SizedBox(height: AppSpacing.sm),
        _pickerRow(
          icon: Icons.person_outline,
          label: _loadingAudienceOptions ? 'Loading people…' : (_individualIds.isEmpty ? 'Select students or trainers' : '${_individualIds.length} selected'),
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
            if (picked != null) {
              setState(() => _individualIds = picked);
              _audienceChanged();
            }
          },
        ),
      ],
    ];
  }

  Widget _recipientBanner() {
    final palette = context.palette;
    final count = _recipientCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 10),
      decoration: BoxDecoration(
        color: palette.goldSoft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_outlined, size: 15, color: palette.gold),
          const SizedBox(width: AppSpacing.md),
          Text(
            count == null ? 'Counting recipients…' : '$count recipient${count == 1 ? '' : 's'}',
            style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.gold),
          ),
        ],
      ),
    );
  }

  Widget _messageField() {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: _bodyController,
          maxLines: 5,
          minLines: 4,
          maxLength: _maxBodyLength,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: AppType.xl, height: 1.5, color: palette.text),
          decoration: InputDecoration(
            hintText: 'Write your announcement…',
            hintStyle: TextStyle(color: palette.textFaint),
            counterText: '',
            filled: true,
            fillColor: palette.surfaceRaised,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.xl), borderSide: BorderSide(color: palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.xl), borderSide: BorderSide(color: palette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.xl), borderSide: BorderSide(color: palette.gold)),
          ),
        ),
        const SizedBox(height: 4),
        Text('${_bodyController.text.length}/$_maxBodyLength', style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
      ],
    );
  }

  Widget _pickerRow({required IconData icon, required String label, required VoidCallback onTap, Color? accent}) {
    final palette = context.palette;
    final color = accent ?? palette.gold;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text))),
            Icon(Icons.chevron_right, size: 16, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}

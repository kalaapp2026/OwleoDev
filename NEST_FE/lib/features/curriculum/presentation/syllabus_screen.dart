import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/curriculum/data/syllabus_api.dart';
import 'package:nest_fe/features/curriculum/data/syllabus_unit.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:url_launcher/url_launcher.dart';

final syllabusApiProvider = Provider((ref) => SyllabusApi(ref.watch(dioClientProvider)));

/// (courseId, membershipId) - null membershipId is the Admin/Trainer management view (everything
/// regardless of targeting); a real membershipId is the scoped read-only view.
final syllabusForCourseProvider = FutureProvider.autoDispose.family<List<SyllabusUnit>, (String, String?)>((ref, params) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(syllabusApiProvider).listForCourse(params.$1, membershipId: params.$2);
});

final tracksForUnitProvider = FutureProvider.autoDispose.family<List<Track>, String>((ref, unitId) {
  return ref.watch(syllabusApiProvider).listTracks(unitId);
});

final attachmentsForUnitProvider = FutureProvider.autoDispose.family<List<MaterialAttachment>, String>((ref, unitId) {
  return ref.watch(syllabusApiProvider).listAttachments(unitId);
});

Future<void> _openUrl(BuildContext context, String? relativeUrl) async {
  final url = ApiConfig.resolveMediaUrl(relativeUrl);
  if (url == null) return;
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) AppNotice.error(context, 'Could not open this file.');
  }
}

/// Course Materials: Academy Admin and any Trainer holding SYLLABUS_EDIT can create/edit/delete;
/// everyone else gets read + download access only. A material targets either the whole course
/// (anyone enrolled sees it) or a multi-select of specific batches within it.
class SyllabusScreen extends ConsumerStatefulWidget {
  const SyllabusScreen({super.key});

  @override
  ConsumerState<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends ConsumerState<SyllabusScreen> {
  String? _loadedCourseId;
  late final _audioPlayer = AudioPlayer();
  String? _playingTrackId;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(Track track) async {
    if (_playingTrackId == track.id) {
      await _audioPlayer.pause();
      setState(() => _playingTrackId = null);
      return;
    }
    final url = ApiConfig.resolveMediaUrl(track.url);
    if (url == null) return;
    await _audioPlayer.play(UrlSource(url));
    setState(() => _playingTrackId = track.id);
  }

  /// +10s/-10s skip on whichever track is currently loaded - clamped at zero so rewinding past
  /// the start doesn't throw.
  Future<void> _seek(Duration offset) async {
    final position = await _audioPlayer.getCurrentPosition() ?? Duration.zero;
    final target = position + offset;
    await _audioPlayer.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    final isAdmin = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
    final canEdit = user != null && (isAdmin || user.hasFeature(FeatureKeys.syllabusEdit));
    // Only an Academy Admin picks from every course in the academy - everyone else (Student or
    // Trainer) only ever sees courses they're actually mapped to, same as the Fees screen's
    // course picker.
    final coursesAsync = isAdmin || user?.activeMembershipId == null
        ? ref.watch(activeCoursesProvider)
        : ref.watch(coursesForMembershipProvider(user!.activeMembershipId!));

    return Scaffold(
      appBar: AppBar(title: const Text('Course materials')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: coursesAsync.when(
              data: (courses) {
                if (courses.isEmpty) {
                  return const Text('No active courses in this academy yet - create one first.', style: TextStyle(fontSize: 12.5));
                }
                final validValue = courses.any((c) => c.id == _loadedCourseId) ? _loadedCourseId : null;
                return DropdownButtonFormField<String>(
                  initialValue: validValue,
                  decoration: const InputDecoration(labelText: 'Course'),
                  items: courses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (id) => setState(() => _loadedCourseId = id),
                );
              },
              loading: () => const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              error: (err, stack) => Text(
                err is ApiException ? err.message : 'Could not load courses',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          if (_loadedCourseId != null && _loadedCourseId!.isNotEmpty)
            Expanded(
              child: _MaterialsList(
                courseId: _loadedCourseId!,
                canEdit: canEdit,
                membershipId: user?.activeMembershipId,
                playingTrackId: _playingTrackId,
                onTogglePlay: _togglePlay,
                onSeek: _seek,
              ),
            ),
        ],
      ),
      floatingActionButton: _loadedCourseId == null || !canEdit
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showMaterialFormSheet(context, ref, courseId: _loadedCourseId!),
              icon: const Icon(Icons.add),
              label: const Text('Add material'),
            ),
    );
  }
}

class _MaterialsList extends ConsumerWidget {
  const _MaterialsList({
    required this.courseId,
    required this.canEdit,
    required this.membershipId,
    required this.playingTrackId,
    required this.onTogglePlay,
    required this.onSeek,
  });

  final String courseId;
  final bool canEdit;
  final String? membershipId;
  final String? playingTrackId;
  final Future<void> Function(Track track) onTogglePlay;
  final Future<void> Function(Duration offset) onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listKey = (courseId, canEdit ? null : membershipId);
    final unitsAsync = ref.watch(syllabusForCourseProvider(listKey));

    return AsyncValueView<List<SyllabusUnit>>(
      value: unitsAsync,
      onRetry: () => ref.invalidate(syllabusForCourseProvider(listKey)),
      data: (context, units) {
        if (units.isEmpty) {
          return EmptyState(
            icon: Icons.menu_book_outlined,
            message: canEdit ? 'No course materials yet - add the first one.' : 'No course materials available to you yet.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: units.length,
          itemBuilder: (context, index) => _MaterialCard(
            unit: units[index],
            courseId: courseId,
            canEdit: canEdit,
            playingTrackId: playingTrackId,
            onTogglePlay: onTogglePlay,
            onSeek: onSeek,
          ),
        );
      },
    );
  }
}

class _MaterialCard extends ConsumerWidget {
  const _MaterialCard({
    required this.unit,
    required this.courseId,
    required this.canEdit,
    required this.playingTrackId,
    required this.onTogglePlay,
    required this.onSeek,
  });

  final SyllabusUnit unit;
  final String courseId;
  final bool canEdit;
  final String? playingTrackId;
  final Future<void> Function(Track track) onTogglePlay;
  final Future<void> Function(Duration offset) onSeek;

  Future<void> _pickAndUploadAttachment(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;
    try {
      await ref.read(syllabusApiProvider).addAttachment(unit.id, picked.bytes!, picked.name);
      ref.invalidate(attachmentsForUnitProvider(unit.id));
      if (context.mounted) AppNotice.success(context, 'Attachment uploaded.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _deleteUnit(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppNotice.confirm(
      context,
      title: 'Delete this material?',
      message: '"${unit.title}" and any songs attached to it will be permanently removed.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(syllabusApiProvider).deleteUnit(unit.id);
      ref.invalidate(syllabusForCourseProvider((courseId, null)));
      if (context.mounted) AppNotice.success(context, 'Deleted.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 14, child: Text('${unit.orderIndex}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Text(unit.title, style: Theme.of(context).textTheme.titleMedium)),
                if (canEdit)
                  PopupMenuButton<String>(
                    onSelected: (action) async {
                      switch (action) {
                        case 'edit':
                          showMaterialFormSheet(context, ref, courseId: courseId, existing: unit);
                        case 'delete':
                          _deleteUnit(context, ref);
                        case 'NOT_STARTED':
                        case 'IN_PROGRESS':
                        case 'COMPLETED':
                          await ref.read(syllabusApiProvider).setStatus(unit.id, action);
                          ref.invalidate(syllabusForCourseProvider((courseId, null)));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'NOT_STARTED', child: Text('Mark: Not started')),
                      PopupMenuItem(value: 'IN_PROGRESS', child: Text('Mark: In progress')),
                      PopupMenuItem(value: 'COMPLETED', child: Text('Mark: Completed')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            if (unit.description != null && unit.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(unit.description!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(unit.isCourseWide ? 'Whole course' : '${unit.batchIds.length} batch(es)'),
                  avatar: Icon(unit.isCourseWide ? Icons.public : Icons.groups_2_outlined, size: 16),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(unit.status.replaceAll('_', ' ')),
                ),
              ],
            ),
            _AttachmentList(unitId: unit.id, canEdit: canEdit),
            _TrackList(unitId: unit.id, canEdit: canEdit, playingTrackId: playingTrackId, onTogglePlay: onTogglePlay, onSeek: onSeek),
            if (canEdit) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickAndUploadAttachment(context, ref),
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: const Text('Attach PDF/image'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showAddTrackSheet(context, ref, unitId: unit.id),
                    icon: const Icon(Icons.music_note_outlined, size: 16),
                    label: const Text('Add song'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A material's PDF/image attachments - a unit can carry several, each its own tappable row.
class _AttachmentList extends ConsumerWidget {
  const _AttachmentList({required this.unitId, required this.canEdit});

  final String unitId;
  final bool canEdit;

  Future<void> _deleteAttachment(BuildContext context, WidgetRef ref, MaterialAttachment attachment) async {
    try {
      await ref.read(syllabusApiProvider).deleteAttachment(unitId, attachment.id);
      ref.invalidate(attachmentsForUnitProvider(unitId));
      if (context.mounted) AppNotice.success(context, 'Attachment removed.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final attachmentsAsync = ref.watch(attachmentsForUnitProvider(unitId));
    return attachmentsAsync.when(
      data: (attachments) {
        if (attachments.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Attachments', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              ...attachments.map((attachment) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => _openUrl(context, attachment.url),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              attachment.materialType == ReferenceMaterialType.pdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(attachment.materialType == ReferenceMaterialType.pdf ? 'PDF' : 'Image', overflow: TextOverflow.ellipsis),
                            ),
                            if (canEdit)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'Remove',
                                onPressed: () => _deleteAttachment(context, ref, attachment),
                              )
                            else
                              const Icon(Icons.open_in_new, size: 16),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

class _TrackList extends ConsumerWidget {
  const _TrackList({
    required this.unitId,
    required this.canEdit,
    required this.playingTrackId,
    required this.onTogglePlay,
    required this.onSeek,
  });

  final String unitId;
  final bool canEdit;
  final String? playingTrackId;
  final Future<void> Function(Track track) onTogglePlay;
  final Future<void> Function(Duration offset) onSeek;

  Future<void> _deleteTrack(BuildContext context, WidgetRef ref, Track track) async {
    try {
      await ref.read(syllabusApiProvider).deleteTrack(unitId, track.id);
      ref.invalidate(tracksForUnitProvider(unitId));
      if (context.mounted) AppNotice.success(context, 'Song removed.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(tracksForUnitProvider(unitId));
    return tracksAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Songs', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              ...tracks.map((track) {
                final isPlaying = playingTrackId == track.id;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: isPlaying
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10, size: 22),
                              tooltip: 'Back 10s',
                              onPressed: () => onSeek(const Duration(seconds: -10)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.pause_circle_filled, size: 28),
                              onPressed: () => onTogglePlay(track),
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_10, size: 22),
                              tooltip: 'Forward 10s',
                              onPressed: () => onSeek(const Duration(seconds: 10)),
                            ),
                          ],
                        )
                      : IconButton(
                          icon: const Icon(Icons.play_circle_fill, size: 28),
                          onPressed: () => onTogglePlay(track),
                        ),
                  title: Text(track.title),
                  subtitle: Text(track.streamOnly ? 'Play only' : 'Downloadable'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!track.streamOnly)
                        IconButton(
                          icon: const Icon(Icons.download_outlined, size: 20),
                          tooltip: 'Download',
                          onPressed: () => _openUrl(context, track.url),
                        ),
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Remove',
                          onPressed: () => _deleteTrack(context, ref, track),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

/// Create/edit sheet for a material - title/description/targeting (whole course, or a multi-select
/// of specific batches). The PDF/image attachment and songs are separate follow-up actions from
/// the material's own menu, not part of this form.
Future<void> showMaterialFormSheet(BuildContext context, WidgetRef ref, {required String courseId, SyllabusUnit? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MaterialFormSheet(courseId: courseId, existing: existing),
  );
}

class _MaterialFormSheet extends ConsumerStatefulWidget {
  const _MaterialFormSheet({required this.courseId, this.existing});
  final String courseId;
  final SyllabusUnit? existing;

  @override
  ConsumerState<_MaterialFormSheet> createState() => _MaterialFormSheetState();
}

class _MaterialFormSheetState extends ConsumerState<_MaterialFormSheet> {
  late final _titleController = TextEditingController(text: widget.existing?.title);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _orderController = TextEditingController(text: (widget.existing?.orderIndex ?? 0).toString());
  late final Set<String> _selectedBatchIds = Set.of(widget.existing?.batchIds ?? const {});
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      AppNotice.error(context, 'Give this material a title.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await ref.read(syllabusApiProvider).updateUnit(
              unitId: widget.existing!.id,
              batchIds: _selectedBatchIds,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              orderIndex: int.tryParse(_orderController.text.trim()) ?? 0,
            );
      } else {
        await ref.read(syllabusApiProvider).createUnit(
              courseId: widget.courseId,
              batchIds: _selectedBatchIds,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              orderIndex: int.tryParse(_orderController.text.trim()) ?? 0,
            );
      }
      ref.invalidate(syllabusForCourseProvider((widget.courseId, null)));
      if (mounted) {
        AppNotice.success(context, _isEditing ? 'Material updated.' : 'Material added.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Edit material' : 'New material', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _orderController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Display order'),
            ),
            const SizedBox(height: 16),
            Text('Visible to', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Leave every batch unselected to make this visible to the whole course, or pick specific '
              'batches to restrict it to just their students.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final batchesAsync = ref.watch(batchesForCourseProvider(widget.courseId));
                return batchesAsync.when(
                  data: (batches) {
                    if (batches.isEmpty) {
                      return const Text('No batches under this course yet - this will apply to the whole course.', style: TextStyle(fontSize: 12.5));
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: batches.map((Batch b) {
                        final selected = _selectedBatchIds.contains(b.id);
                        return FilterChip(
                          label: Text(b.name),
                          selected: selected,
                          onSelected: (v) => setState(() => v ? _selectedBatchIds.add(b.id) : _selectedBatchIds.remove(b.id)),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (err, stack) => const Text('Could not load batches for this course.', style: TextStyle(fontSize: 12.5)),
                );
              },
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Save changes' : 'Add material'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Add song" sheet - title, a play-only-or-downloadable toggle, and the audio file itself.
Future<void> showAddTrackSheet(BuildContext context, WidgetRef ref, {required String unitId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddTrackSheet(unitId: unitId),
  );
}

class _AddTrackSheet extends ConsumerStatefulWidget {
  const _AddTrackSheet({required this.unitId});
  final String unitId;

  @override
  ConsumerState<_AddTrackSheet> createState() => _AddTrackSheetState();
}

class _AddTrackSheetState extends ConsumerState<_AddTrackSheet> {
  final _titleController = TextEditingController();
  bool _allowDownload = false;
  bool _isSaving = false;
  Uint8List? _fileBytes;
  String? _fileName;

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(type: FileType.audio, withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;
    setState(() {
      _fileBytes = picked.bytes;
      _fileName = picked.name;
    });
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      AppNotice.error(context, 'Give this song a title.');
      return;
    }
    if (_fileBytes == null || _fileName == null) {
      AppNotice.error(context, 'Pick an audio file first.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(syllabusApiProvider).addTrack(
            unitId: widget.unitId,
            title: _titleController.text.trim(),
            streamOnly: !_allowDownload,
            bytes: _fileBytes!,
            filename: _fileName!,
          );
      ref.invalidate(tracksForUnitProvider(widget.unitId));
      if (mounted) {
        AppNotice.success(context, 'Song added.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a song', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Song title')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.audiotrack_outlined),
            label: Text(_fileName ?? 'Choose audio file'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow download'),
            subtitle: const Text('Off = students can only play it from the app'),
            value: _allowDownload,
            onChanged: (v) => setState(() => _allowDownload = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add song'),
          ),
        ],
      ),
    );
  }
}

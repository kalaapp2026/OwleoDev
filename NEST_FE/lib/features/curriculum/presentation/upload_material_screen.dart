import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';

/// Cap borrowed from the prototype. A material's note is an orientation line on a list row, not
/// a lesson plan.
const _descriptionLimit = 100;

/// Upload a new file, or edit an existing one's details.
///
/// Editing deliberately cannot swap the file: the title, note and permission describe *this*
/// upload, and silently replacing the bytes under them would leave students who already opened it
/// with a stale copy and no indication anything changed. Replacing means uploading again.
class UploadMaterialScreen extends ConsumerStatefulWidget {
  const UploadMaterialScreen({super.key, required this.summary, this.existing});

  final BatchMaterialSummary summary;
  final StudyMaterial? existing;

  @override
  ConsumerState<UploadMaterialScreen> createState() => _UploadMaterialScreenState();
}

class _UploadMaterialScreenState extends ConsumerState<UploadMaterialScreen> {
  late final _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');

  late StudyMaterialPermission _permission =
      widget.existing?.permission ?? StudyMaterialPermission.downloadable;

  /// Whether the admin has touched the permission control. Until they do, picking an audio file
  /// moves it to view-only on their behalf; after that their choice stands.
  late bool _permissionTouched = widget.existing != null;

  /// Same idea for the title - derived from the filename until typed into.
  late bool _titleTouched = widget.existing != null;

  Uint8List? _bytes;
  String? _fileName;
  int? _fileSize;
  bool _busy = false;

  bool get _isEditing => widget.existing != null;

  StudyMaterialType? get _fileType {
    final name = _fileName ?? widget.existing?.fileName;
    return name == null ? null : _typeOf(name);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Mirrors the backend's classification, which is by extension rather than content type -
  /// browsers report mp3 as any of three different types depending on platform.
  static StudyMaterialType _typeOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return StudyMaterialType.notes;
    final ext = fileName.substring(dot + 1).toLowerCase();
    if (const {'mp3', 'wav', 'm4a', 'aac', 'ogg'}.contains(ext)) {
      return StudyMaterialType.audio;
    }
    if (const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)) {
      return StudyMaterialType.image;
    }
    return StudyMaterialType.notes;
  }

  static String _titleFrom(String fileName) {
    final withoutExtension = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final spaced =
        withoutExtension.replaceAll(RegExp(r'[-_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return spaced.isEmpty ? fileName : spaced;
  }

  Future<void> _pickFile() async {
    // withData so the bytes come back directly - the upload sends bytes rather than a path, which
    // is the only form that works identically on web and on device.
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;

    setState(() {
      _bytes = file.bytes;
      _fileName = file.name;
      _fileSize = file.size;
      if (!_titleTouched) _titleController.text = _titleFrom(file.name);
      // Audio defaults to view-only: a backing track is the file most likely to be passed on,
      // and the control right below makes the choice easy to override.
      if (!_permissionTouched && _typeOf(file.name) == StudyMaterialType.audio) {
        _permission = StudyMaterialPermission.viewOnly;
      }
    });
  }

  bool get _valid =>
      _titleController.text.trim().isNotEmpty &&
      (_isEditing || _bytes != null);

  String _missing() {
    if (!_isEditing && _bytes == null) return 'Choose a file to upload.';
    return 'Give this material a title.';
  }

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    final api = ref.read(studyMaterialApiProvider);
    final description = _descriptionController.text.trim();

    try {
      if (_isEditing) {
        await api.update(
          widget.existing!.id,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          permission: _permission,
        );
      } else {
        await api.upload(
          batchId: widget.summary.batchId,
          bytes: _bytes!,
          fileName: _fileName!,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          permission: _permission,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isEditing ? 'Edit Material' : 'Upload Material',
                style: TextStyle(
                    fontSize: 17, fontWeight: AppType.bold, color: palette.text)),
            Text('${widget.summary.batchName} · ${widget.summary.courseName ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.x3l, AppSpacing.page, AppSpacing.x5l),
        children: [
          _Field(label: 'File', child: _filePicker(palette)),
          _Field(
            label: 'Title',
            child: TextField(
              controller: _titleController,
              onChanged: (_) => setState(() => _titleTouched = true),
              style: TextStyle(
                  fontSize: AppType.xxl,
                  fontWeight: AppType.medium,
                  color: palette.text),
              decoration: _decoration(palette, 'e.g. Chord Chart - Week 1'),
            ),
          ),
          _Field(
            label: 'Notes for students (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  maxLength: _descriptionLimit,
                  onChanged: (_) => setState(() {}),
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  style: TextStyle(
                      fontSize: AppType.lg,
                      fontWeight: AppType.regular,
                      height: 1.5,
                      color: palette.text),
                  decoration: _decoration(
                      palette, 'Briefly describe this file (up to 100 characters)'),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${_descriptionController.text.length}/$_descriptionLimit characters',
                  style: TextStyle(
                    fontSize: AppType.xs,
                    color: _descriptionController.text.length >= _descriptionLimit
                        ? palette.notPaid
                        : palette.textFaint,
                  ),
                ),
              ],
            ),
          ),
          _Field(
            label: 'Student access',
            hint: _permission.explanation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSegmentedControl<StudyMaterialPermission>(
                  options: StudyMaterialPermission.values,
                  labelOf: (p) => p.label,
                  isSelected: (p) => p == _permission,
                  activeColorOf: (context, p) => p.color(context.palette),
                  activeTextColorOf: (context, _) => context.palette.onPrimary,
                  onTap: (p) => setState(() {
                    _permission = p;
                    _permissionTouched = true;
                  }),
                ),
                if (_fileType == StudyMaterialType.audio &&
                    _permission == StudyMaterialPermission.viewOnly) ...[
                  const SizedBox(height: AppSpacing.md),
                  _audioNotice(palette),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppPrimaryButton(
            label: _isEditing ? 'Save changes' : 'Upload',
            icon: _isEditing ? Icons.check : Icons.cloud_upload_outlined,
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

  Widget _filePicker(AppPalette palette) {
    final name = _fileName ?? widget.existing?.fileName;
    final type = _fileType;

    if (name == null) {
      return Pressable(
        onTap: _pickFile,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.x5l),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(Icons.cloud_upload_outlined, size: 22, color: palette.primary),
              const SizedBox(height: AppSpacing.sm),
              Text('Tap to choose a file',
                  style: TextStyle(
                      fontSize: AppType.lg,
                      fontWeight: AppType.bold,
                      color: palette.text)),
              const SizedBox(height: 2),
              Text('PDF, DOC, image or audio',
                  style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
            ],
          ),
        ),
      );
    }

    final sizeLabel = _fileSize != null
        ? _formatSize(_fileSize!)
        : widget.existing?.sizeLabel ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: type?.softColor(palette) ?? palette.surfaceHigh,
              borderRadius: AppRadii.all(AppRadii.md),
            ),
            child: Icon(type?.icon ?? Icons.description_outlined,
                size: 16, color: type?.color(palette) ?? palette.textMuted),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppType.semi,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text([sizeLabel, type?.label].whereType<String>().join(' · '),
                    style:
                        TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
              ],
            ),
          ),
          if (!_isEditing)
            Pressable(
              onTap: _pickFile,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.md),
                  border: Border.all(color: palette.border),
                ),
                child: Text('Replace',
                    style: TextStyle(
                        fontSize: AppType.sm,
                        fontWeight: AppType.bold,
                        color: palette.primary)),
              ),
            ),
        ],
      ),
    );
  }

  /// Explains the audio default rather than leaving it to look like a bug when the control moves
  /// on its own.
  Widget _audioNotice(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.violetSoft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.violet.withValues(alpha: 0.27)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: palette.violet),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              "Audio defaults to view only, so students can't download and redistribute it. "
              "Switch to Downloadable above if that's not needed here.",
              style: TextStyle(
                  fontSize: AppType.sm, color: palette.text, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.ceil()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  InputDecoration _decoration(AppPalette palette, String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
            fontSize: AppType.lg,
            fontWeight: AppType.regular,
            color: palette.textFaint),
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
                    fontSize: AppType.sm, color: palette.textFaint, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

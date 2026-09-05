import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/curriculum/presentation/upload_material_screen.dart';

enum MaterialSort {
  newest('Newest first'),
  oldest('Oldest first'),
  az('A - Z'),
  za('Z - A');

  const MaterialSort(this.label);
  final String label;
}

/// One batch's shared files.
///
/// [studentPreview] renders it the way a student sees it - no kebab, no permission toggles, just
/// the list. Borrowed from Google Forms' preview: the only reliable way to know what you've
/// actually shared is to look at it as the person receiving it.
class BatchMaterialScreen extends ConsumerStatefulWidget {
  const BatchMaterialScreen({
    super.key,
    required this.summary,
    this.studentPreview = false,
  });

  final BatchMaterialSummary summary;

  /// Renders it the way a student sees it while the caller is still an editor - the deliberate
  /// 'preview as student' action.
  final bool studentPreview;

  @override
  ConsumerState<BatchMaterialScreen> createState() => _BatchMaterialScreenState();
}

class _BatchMaterialScreenState extends ConsumerState<BatchMaterialScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  MaterialSort _sort = MaterialSort.newest;
  StudyMaterialType? _typeFilter;
  String? _kebabFor;

  BatchMaterialSummary get summary => widget.summary;

  /// True when this render must hide every editing affordance - either because the caller asked
  /// to preview it as a student, or because they genuinely cannot edit.
  ///
  /// The second half became load-bearing when Course Materials merged in: the tile used to be
  /// gated on SYLLABUS_EDIT, so only editors ever arrived here. Everyone reads it now, and an
  /// upload button that 403s is worse than no button.
  bool get _readOnly {
    if (widget.studentPreview) return true;
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return true;
    if (user.isSuperAdmin || user.isActiveAcademyAdmin) return false;
    return !user.hasFeature(FeatureKeys.syllabusEdit);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(batchMaterialsProvider(summary.batchId));

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _openUpload({StudyMaterial? existing}) async {
    setState(() => _kebabFor = null);
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => UploadMaterialScreen(summary: summary, existing: existing),
    ));
    if (saved == true) {
      _refresh();
      if (mounted) {
        showAppToast(context, existing == null ? 'Material uploaded' : 'Material updated');
      }
    }
  }

  Future<void> _togglePermission(StudyMaterial material) async {
    setState(() => _kebabFor = null);
    final next = material.isDownloadable
        ? StudyMaterialPermission.viewOnly
        : StudyMaterialPermission.downloadable;
    try {
      await ref.read(studyMaterialApiProvider).update(
            material.id,
            title: material.title,
            description: material.description,
            permission: next,
          );
      _refresh();
      if (mounted) showAppToast(context, 'Marked as ${next.label.toLowerCase()}');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _requestDelete(StudyMaterial material) async {
    setState(() => _kebabFor = null);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete this file?',
      message: '"${material.title}" will be permanently removed for students in this '
          "batch. This can't be undone.",
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(studyMaterialApiProvider).delete(material.id);
      _refresh();
      if (mounted) showAppToast(context, 'File deleted');
    } catch (e) {
      _showError(e);
    }
  }

  List<StudyMaterial> _visible(List<StudyMaterial> all) {
    final q = _query.trim().toLowerCase();
    final filtered = all.where((m) {
      if (_typeFilter != null && m.fileType != _typeFilter) return false;
      if (q.isEmpty) return true;
      return '${m.title} ${m.fileName}'.toLowerCase().contains(q);
    }).toList();

    filtered.sort((a, b) => switch (_sort) {
          MaterialSort.az => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          MaterialSort.za => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
          MaterialSort.oldest => a.uploadedAt.compareTo(b.uploadedAt),
          MaterialSort.newest => b.uploadedAt.compareTo(a.uploadedAt),
        });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = summary.courseCategory.meta(palette);
    final async = ref.watch(batchMaterialsProvider(summary.batchId));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(summary.batchName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 17, fontWeight: AppType.bold, color: palette.text)),
            Text(summary.courseName ?? 'Unlinked course',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
        actions: [
          if (!_readOnly)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.page),
              child: Center(
                child: AppIconButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'Preview as student',
                  size: 38,
                  iconSize: 16,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BatchMaterialScreen(
                        summary: summary, studentPreview: true),
                  )),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _readOnly
          ? null
          : Pressable(
              onTap: () => _openUpload(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4l, vertical: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: AppRadii.all(AppRadii.pill),
                  boxShadow: AppShadows.dropdown,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_upload_outlined,
                        size: 17, color: palette.onPrimary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Upload Material',
                        style: TextStyle(
                            fontSize: AppType.xxl,
                            fontWeight: AppType.bold,
                            color: palette.onPrimary)),
                  ],
                ),
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.studentPreview) _previewBanner(palette),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.x4l),
                  child: Text(e.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
                ),
              ),
              data: (materials) {
                final visible = _visible(materials);
                return GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onTap: () => setState(() => _kebabFor = null),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                        AppSpacing.xl, AppSpacing.page, AppSpacing.listBottom + 40),
                    children: [
                      if (!_readOnly) ...[
                        _permissionStats(palette, materials),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      _searchAndSort(palette),
                      const SizedBox(height: AppSpacing.md),
                      _typeFilters(palette),
                      const SizedBox(height: AppSpacing.lg),
                      if (visible.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: AppSpacing.x5l),
                          child: Text(
                            materials.isEmpty
                                ? _readOnly
                                    ? 'No study material has been shared with this batch yet.'
                                    : 'No study material yet. Upload notes, audio or images for '
                                        'this batch below.'
                                : 'No files match this search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: AppType.lg,
                                color: palette.textFaint,
                                height: 1.6),
                          ),
                        )
                      else
                        for (final material in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _MaterialRow(
                              material: material,
                              accent: meta.color,
                              studentPreview: _readOnly,
                              kebabOpen: _kebabFor == material.id,
                              onToggleKebab: () => setState(() => _kebabFor =
                                  _kebabFor == material.id ? null : material.id),
                              onEdit: () => _openUpload(existing: material),
                              onTogglePermission: () => _togglePermission(material),
                              onDelete: () => _requestDelete(material),
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBanner(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl, vertical: 9),
      decoration: BoxDecoration(
        color: palette.primarySoft,
        border: Border(bottom: BorderSide(color: palette.primary.withValues(alpha: 0.33))),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 13, color: palette.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Previewing as Student',
                style: TextStyle(
                    fontSize: AppType.sm,
                    fontWeight: AppType.bold,
                    color: palette.primary)),
          ),
          Pressable(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: AppRadii.all(AppRadii.sm),
                border:
                    Border.all(color: palette.primary.withValues(alpha: 0.4)),
              ),
              child: Text('Exit preview',
                  style: TextStyle(
                      fontSize: AppType.xs,
                      fontWeight: AppType.bold,
                      color: palette.primary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionStats(AppPalette palette, List<StudyMaterial> materials) {
    final downloadable = materials.where((m) => m.isDownloadable).length;
    final viewOnly = materials.length - downloadable;

    Widget pill(StudyMaterialPermission permission, int count) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: permission.softColor(palette),
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(
                  color: permission.color(palette).withValues(alpha: 0.27)),
            ),
            child: Row(
              children: [
                Icon(permission.icon, size: 15, color: permission.color(palette)),
                const SizedBox(width: AppSpacing.sm),
                Text('$count',
                    style: TextStyle(
                        fontSize: AppType.x3l,
                        fontWeight: AppType.heavy,
                        height: 1,
                        color: permission.color(palette))),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(permission.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.sm,
                        fontWeight: AppType.bold,
                        letterSpacing: 0.3,
                        height: 1,
                        color: permission.color(palette),
                      )),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        pill(StudyMaterialPermission.downloadable, downloadable),
        const SizedBox(width: AppSpacing.sm),
        pill(StudyMaterialPermission.viewOnly, viewOnly),
      ],
    );
  }

  Widget _searchAndSort(AppPalette palette) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 14, color: palette.textFaint),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppType.regular,
                        color: palette.text),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Search files',
                      hintStyle:
                          TextStyle(fontSize: AppType.lg, color: palette.textFaint),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  Pressable(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child:
                        Icon(Icons.close_rounded, size: 13, color: palette.textFaint),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AttachedSelect<MaterialSort>(
          label: 'Sort',
          options: MaterialSort.values,
          labelOf: (s) => s.label,
          value: _sort,
          panelWidth: 200,
          panelSpan: PanelSpan.right,
          onSelected: (s) => setState(() => _sort = s),
          optionBuilder: (context, option, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(option.label,
                  style: TextStyle(
                    fontSize: AppType.xl,
                    fontWeight: _sort == option ? AppType.bold : AppType.regular,
                    color: _sort == option ? palette.primary : palette.text,
                  )),
              if (_sort == option)
                Icon(Icons.check, size: 15, color: palette.primary),
            ],
          ),
          triggerBuilder: (context, isOpen, toggle) => AppIconButton(
            icon: Icons.swap_vert,
            tooltip: _sort.label,
            onTap: toggle,
            size: 38,
            iconSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _typeFilters(AppPalette palette) {
    Widget chip(StudyMaterialType? type) {
      final active = _typeFilter == type;
      final color = type?.color(palette) ?? palette.primary;
      final soft = type?.softColor(palette) ?? palette.primarySoft;
      return Expanded(
        child: Pressable(
          onTap: () => setState(() => _typeFilter = active ? null : type),
          child: AnimatedContainer(
            duration: AppMotion.fade,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: 7),
            decoration: BoxDecoration(
              color: active ? soft : palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: active ? color : palette.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (type != null) ...[
                  Icon(type.icon,
                      size: 11, color: active ? color : palette.textMuted),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Flexible(
                  child: Text(type?.label ?? 'All',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.sm,
                        fontWeight: AppType.bold,
                        color: active ? color : palette.textMuted,
                      )),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(null),
        const SizedBox(width: AppSpacing.xs),
        chip(StudyMaterialType.notes),
        const SizedBox(width: AppSpacing.xs),
        chip(StudyMaterialType.audio),
        const SizedBox(width: AppSpacing.xs),
        chip(StudyMaterialType.image),
      ],
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.accent,
    required this.studentPreview,
    required this.kebabOpen,
    required this.onToggleKebab,
    required this.onEdit,
    required this.onTogglePermission,
    required this.onDelete,
  });

  final StudyMaterial material;
  final Color accent;
  final bool studentPreview;
  final bool kebabOpen;
  final VoidCallback onToggleKebab;
  final VoidCallback onEdit;
  final VoidCallback onTogglePermission;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = material.fileType;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: type.softColor(palette),
              borderRadius: AppRadii.all(AppRadii.lg),
            ),
            child: Icon(type.icon, size: 18, color: type.color(palette)),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(material.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.xl,
                        fontWeight: AppType.semi,
                        color: palette.text)),
                if (material.description != null) ...[
                  const SizedBox(height: 2),
                  Text(material.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.sm,
                          color: palette.textMuted,
                          height: 1.4)),
                ],
                const SizedBox(height: 3),
                Text(
                  [
                    material.sizeLabel,
                    formatFeeDate(material.uploadedAt),
                    if (!studentPreview && material.uploadedByName != null)
                      material.uploadedByName!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
                ),
                const SizedBox(height: 7),
                _permissionBadge(palette),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (studentPreview)
            // A student sees only what they can do with it, not who set it that way.
            Icon(material.permission.icon, size: 16, color: palette.textMuted)
          else
            _kebab(palette),
        ],
      ),
    );
  }

  Widget _permissionBadge(AppPalette palette) {
    final permission = material.permission;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: permission.softColor(palette),
        borderRadius: AppRadii.all(AppRadii.pill),
        border:
            Border.all(color: permission.color(palette).withValues(alpha: 0.33)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(permission.icon, size: 10.5, color: permission.color(palette)),
          const SizedBox(width: AppSpacing.xxs),
          Text(permission.label,
              style: TextStyle(
                fontSize: AppType.tiny,
                fontWeight: AppType.heavy,
                color: permission.color(palette),
              )),
        ],
      ),
    );
  }

  Widget _kebab(AppPalette palette) {
    final actions = <(String, bool, VoidCallback)>[
      ('Edit details', false, onEdit),
      (
        material.isDownloadable ? 'Mark as view only' : 'Mark as downloadable',
        false,
        onTogglePermission
      ),
      ('Delete file', true, onDelete),
    ];

    return AttachedSelect<(String, bool, VoidCallback)>(
      label: '',
      options: actions,
      labelOf: (a) => a.$1,
      isOpen: kebabOpen,
      onOpenChanged: (_) => onToggleKebab(),
      panelWidth: 200,
      panelSpan: PanelSpan.right,
      onSelected: (a) => a.$3(),
      optionBuilder: (context, option, _) => Text(
        option.$1,
        style: TextStyle(
          fontSize: AppType.lg,
          fontWeight: AppType.medium,
          color: option.$2 ? palette.notPaid : palette.text,
        ),
      ),
      triggerBuilder: (context, isOpen, toggle) =>
          AppIconButton(icon: Icons.more_vert, onTap: toggle, size: 30, iconSize: 15),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/curriculum/presentation/file_viewer_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/playlists_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/material_row.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/permission_badge.dart';

enum LibrarySort {
  recent('Recent → Oldest'),
  oldest('Oldest → Recent'),
  az('A → Z'),
  za('Z → A');

  const LibrarySort(this.label);
  final String label;
}

/// One entry in the course filter. [id] null means "all courses".
typedef _CourseOption = ({String? id, String label, CourseCategory? category});

/// One entry in the batch filter. [id] null means "all batches".
typedef _BatchOption = ({String? id, String label});

/// Everything of one type, across every batch.
///
/// The batch screens answer "what was shared with this class". This answers "where is that track"
/// — which is the question actually asked mid-lesson, when the batch it came from is exactly the
/// thing you have forgotten.
class MaterialLibraryScreen extends ConsumerStatefulWidget {
  const MaterialLibraryScreen({super.key, required this.fileType, this.currentMaterialId});

  final StudyMaterialType fileType;

  /// The file the caller is already looking at, marked "Now playing" in the list.
  final String? currentMaterialId;

  @override
  ConsumerState<MaterialLibraryScreen> createState() => _MaterialLibraryScreenState();
}

class _MaterialLibraryScreenState extends ConsumerState<MaterialLibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  LibrarySort _sort = LibrarySort.recent;
  bool _grid = false;
  String? _courseId;
  String? _batchId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.fileType) {
    StudyMaterialType.audio => 'Song Library',
    StudyMaterialType.notes => 'Document Library',
    StudyMaterialType.image => 'Image Library',
  };

  String get _noun => switch (widget.fileType) {
    StudyMaterialType.audio => 'song',
    StudyMaterialType.notes => 'document',
    StudyMaterialType.image => 'image',
  };

  String get _activeLabel =>
      widget.fileType == StudyMaterialType.audio ? 'Now playing' : 'Now viewing';

  void _open(StudyMaterial material) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileViewerScreen(
          material: material,
          // Already came from the library, so "library" just means back.
          onOpenLibrary: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  void _openPlaylists() {
    final route = ModalRoute.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistsScreen(
          onOpenLibrary: () => Navigator.of(context).popUntil((r) => r == route),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(materialLibraryProvider(widget.fileType));
    final batches = ref.watch(materialBatchesProvider).valueOrNull ?? const [];
    final byBatch = {for (final b in batches) b.batchId: b};
    final courses = ref.watch(materialCoursesProvider).valueOrNull ?? const <CourseMaterialSummary>[];

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette, async.valueOrNull?.length),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _searchRow(palette),
                  const SizedBox(height: 10),
                  _filterRow(palette, batches, courses),
                  const SizedBox(height: 10),
                  Text(
                    async.when(
                      data: (all) {
                        final n = _visible(all, byBatch).length;
                        return '$n result${n == 1 ? '' : 's'}';
                      },
                      loading: () => '',
                      error: (_, _) => '',
                    ),
                    style: TextStyle(
                        fontSize: AppType.sm,
                        fontWeight: AppType.semi,
                        color: palette.textFaint),
                  ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4l),
                    child: Text(
                      e.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: AppType.lg, color: palette.textMuted),
                    ),
                  ),
                ),
                data: (all) {
                  final visible = _visible(all, byBatch);
                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          all.isEmpty
                              ? 'No $_noun files uploaded anywhere yet.'
                              : 'No ${_noun}s match these filters.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppType.lg,
                            color: palette.textFaint,
                            height: 1.6,
                          ),
                        ),
                      ),
                    );
                  }
                  return _grid ? _gridView(palette, visible, byBatch) : _listView(visible, byBatch);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- data --------------------------------------------------------------------------------

  List<StudyMaterial> _visible(
    List<StudyMaterial> all,
    Map<String, BatchMaterialSummary> byBatch,
  ) {
    final q = _query.trim().toLowerCase();
    final filtered = all.where((m) {
      if (_courseId != null && !_reachesCourse(m, byBatch, _courseId!)) return false;
      if (_batchId != null && !_reachesBatch(m, byBatch, _batchId!)) return false;
      if (q.isEmpty) return true;
      return m.title.toLowerCase().contains(q) || m.audienceLabel.toLowerCase().contains(q);
    }).toList();

    filtered.sort(
      (a, b) => switch (_sort) {
        LibrarySort.az => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        LibrarySort.za => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        LibrarySort.oldest => a.uploadedAt.compareTo(b.uploadedAt),
        LibrarySort.recent => b.uploadedAt.compareTo(a.uploadedAt),
      },
    );
    return filtered;
  }

  /// A file reaches a course when it was shared with that whole course, or with a batch that covers it.
  bool _reachesCourse(StudyMaterial m, Map<String, BatchMaterialSummary> byBatch, String courseId) =>
      m.courseTargetIds.contains(courseId) ||
      m.batchTargetIds.any((b) => byBatch[b]?.coversCourse(courseId) ?? false);

  /// ...and a batch when it was shared with that batch, or with a whole course the batch covers.
  bool _reachesBatch(StudyMaterial m, Map<String, BatchMaterialSummary> byBatch, String batchId) {
    if (m.batchTargetIds.contains(batchId)) return true;
    final batch = byBatch[batchId];
    return batch != null && m.courseTargetIds.any(batch.coversCourse);
  }

  /// Who it was shared with - "Guitar Advanced · Saturday" - or a plain word when the server named no one.
  String _origin(StudyMaterial m) => m.audienceLabel.isEmpty ? 'Shared' : m.audienceLabel;

  // ---- list / grid -------------------------------------------------------------------------

  Widget _listView(List<StudyMaterial> items, Map<String, BatchMaterialSummary> byBatch) {
    final palette = context.palette;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        final batch = byBatch[m.batchId];
        final active = m.id == widget.currentMaterialId;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: MaterialRow(
            material: m,
            onTap: () => _open(m),
            highlighted: active,
            highlightColor: palette.primary,
            originLine: _origin(m),
            originColor: batch?.courseCategory.meta(palette).color,
            trailing: active
                ? Text(
                    _activeLabel,
                    style: TextStyle(
                      fontSize: AppType.tiny,
                      fontWeight: AppType.heavy,
                      color: palette.primary,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _gridView(
    AppPalette palette,
    List<StudyMaterial> items,
    Map<String, BatchMaterialSummary> byBatch,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 214,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        final batch = byBatch[m.batchId];
        final active = m.id == widget.currentMaterialId;
        final typeColor = m.fileType.color(palette);
        final courseColor = batch?.courseCategory.meta(palette).color;

        return Pressable(
          onTap: () => _open(m),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active ? palette.primarySoft : palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.xxl),
              border: Border.all(color: active ? palette.primary : palette.borderSoft),
            ),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: m.fileType == StudyMaterialType.audio
                      ? _recordTile(palette, typeColor)
                      : Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: m.fileType.softColor(palette),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(m.fileType.icon, size: 26, color: typeColor),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  m.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppType.base,
                    fontWeight: AppType.semi,
                    height: 1.3,
                    color: palette.text,
                  ),
                ),
                if (batch != null && courseColor != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    batch.batchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: AppType.bold,
                      color: courseColor,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  m.sizeLabel,
                  style: TextStyle(fontSize: AppType.micro, color: palette.textFaint),
                ),
                const Spacer(),
                active
                    ? Text(
                        _activeLabel,
                        style: TextStyle(
                          fontSize: AppType.micro,
                          fontWeight: AppType.heavy,
                          color: palette.primary,
                        ),
                      )
                    : PermissionBadge(permission: m.permission),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The little record that stands in for cover art on a song's grid card.
  Widget _recordTile(AppPalette palette, Color typeColor) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withValues(alpha: 0.27)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [StudyMaterialType.audio.softColor(palette), palette.surfaceHigh],
        ),
      ),
      child: FractionallySizedBox(
        widthFactor: 0.64,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.bg,
              shape: BoxShape.circle,
              border: Border.all(color: typeColor, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6)),
              ],
            ),
            child: FractionallySizedBox(
              widthFactor: 0.42,
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: StudyMaterialType.audio.softColor(palette),
                    shape: BoxShape.circle,
                    border: Border.all(color: typeColor, width: 1.5),
                  ),
                  child: Icon(Icons.music_note_outlined, size: 14, color: typeColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- chrome ------------------------------------------------------------------------------

  Widget _header(AppPalette palette, int? count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          AppIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppType.bold,
                    letterSpacing: AppType.titleTracking,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == null
                      ? 'Across all batches'
                      : '$count $_noun${count == 1 ? '' : 's'} across all batches',
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                ),
              ],
            ),
          ),
          if (widget.fileType == StudyMaterialType.audio)
            Pressable(
              onTap: _openPlaylists,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.format_list_numbered, size: 14, color: palette.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Playlists',
                      style: TextStyle(
                        fontSize: AppType.smd,
                        fontWeight: AppType.bold,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchRow(AppPalette palette) {
    Widget viewButton(IconData icon, bool selected, VoidCallback onTap) => Pressable(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        color: selected ? palette.primarySoft : Colors.transparent,
        child: Icon(icon, size: 15, color: selected ? palette.primary : palette.textMuted),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
                      color: palette.text,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Search ${_noun}s, batch or course',
                      hintStyle: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  Pressable(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child: Icon(Icons.close_rounded, size: 13, color: palette.textFaint),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AttachedSelect<LibrarySort>(
          label: 'Sort',
          options: LibrarySort.values,
          labelOf: (s) => s.label,
          value: _sort,
          panelWidth: 190,
          panelSpan: PanelSpan.right,
          showPanelHeader: false,
          onSelected: (s) => setState(() => _sort = s),
          optionBuilder: (context, option, _) => Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: AppType.xl,
                    fontWeight: option == _sort ? AppType.bold : AppType.regular,
                    color: option == _sort ? palette.primary : palette.text,
                  ),
                ),
              ),
              if (option == _sort) Icon(Icons.check, size: 15, color: palette.primary),
            ],
          ),
          triggerBuilder: (context, isOpen, toggle) => AppIconButton(
            icon: Icons.swap_vert,
            tooltip: _sort.label,
            onTap: toggle,
            size: 38,
            iconSize: 14,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: AppRadii.all(AppRadii.lg),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              viewButton(Icons.view_list_outlined, !_grid, () => setState(() => _grid = false)),
              viewButton(Icons.grid_view_outlined, _grid, () => setState(() => _grid = true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterRow(
      AppPalette palette, List<BatchMaterialSummary> batches, List<CourseMaterialSummary> courseSummaries) {
    // Courses and batches come from what the caller can see - the same set the files do. A batch can span
    // several courses, so it is offered under each of them.
    final courses = <_CourseOption>[
      (id: null, label: 'All courses', category: null),
    ];
    final seen = <String>{};
    for (final c in courseSummaries) {
      if (seen.add(c.courseId)) {
        courses.add((id: c.courseId, label: c.courseName, category: c.courseCategory));
      }
    }
    for (final b in batches) {
      for (var i = 0; i < b.courseIds.length; i++) {
        if (seen.add(b.courseIds[i])) {
          courses.add((
            id: b.courseIds[i],
            label: i < b.courseNames.length ? b.courseNames[i] : 'Course',
            category: b.courseIds[i] == b.courseId ? b.courseCategory : null,
          ));
        }
      }
      if (b.courseId != null && seen.add(b.courseId!)) {
        courses.add((id: b.courseId, label: b.courseName ?? 'Course', category: b.courseCategory));
      }
    }
    final batchOptions = <_BatchOption>[
      (id: null, label: 'All batches'),
      for (final b in batches)
        if (_courseId == null || b.coversCourse(_courseId))
          (id: b.batchId, label: '${b.batchName} · ${b.coursesLabel}'),
    ];

    final course = courses.firstWhere((c) => c.id == _courseId, orElse: () => courses.first);
    final batch = batchOptions.firstWhere((b) => b.id == _batchId, orElse: () => batchOptions.first);
    final courseMeta = course.category?.meta(palette);

    Widget trigger({
      required String label,
      required Color color,
      required Color soft,
      required Color border,
      required VoidCallback onTap,
    }) => Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, size: 12, color: color),
          ],
        ),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: AttachedSelect<_CourseOption>(
            label: 'Course',
            options: courses,
            labelOf: (c) => c.label,
            value: course,
            searchable: true,
            searchHint: 'Search course',
            panelWidth: 220,
            onSelected: (c) => setState(() {
              _courseId = c.id;
              _batchId = null;
            }),
            optionBuilder: (context, option, _) {
              final selected = option.id == _courseId;
              final dot = option.category?.meta(palette).color;
              return Row(
                children: [
                  if (dot != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.xl,
                        fontWeight: selected ? AppType.bold : AppType.regular,
                        color: selected ? (dot ?? palette.primary) : palette.text,
                      ),
                    ),
                  ),
                ],
              );
            },
            triggerBuilder: (context, isOpen, toggle) => trigger(
              label: course.label,
              color: courseMeta?.color ?? palette.textMuted,
              soft: courseMeta?.soft ?? palette.surfaceRaised,
              border: courseMeta?.color ?? palette.border,
              onTap: toggle,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AttachedSelect<_BatchOption>(
            label: 'Batch',
            options: batchOptions,
            labelOf: (b) => b.label,
            value: batch,
            searchable: true,
            searchHint: 'Search batch',
            panelWidth: 220,
            panelSpan: PanelSpan.right,
            onSelected: (b) => setState(() => _batchId = b.id),
            optionBuilder: (context, option, _) => Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.xl,
                fontWeight: option.id == _batchId ? AppType.bold : AppType.regular,
                color: option.id == _batchId ? palette.primary : palette.text,
              ),
            ),
            triggerBuilder: (context, isOpen, toggle) => trigger(
              label: batch.label,
              color: _batchId != null ? palette.primary : palette.textMuted,
              soft: _batchId != null ? palette.primarySoft : palette.surfaceRaised,
              border: _batchId != null ? palette.primary : palette.border,
              onTap: toggle,
            ),
          ),
        ),
      ],
    );
  }
}

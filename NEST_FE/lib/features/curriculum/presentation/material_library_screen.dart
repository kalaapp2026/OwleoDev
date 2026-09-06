import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/curriculum/presentation/file_viewer_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/playlists_screen.dart';
import 'package:nest_fe/features/curriculum/presentation/widgets/material_row.dart';

enum LibrarySort {
  newest('Newest first'),
  oldest('Oldest first'),
  az('A - Z'),
  za('Z - A');

  const LibrarySort(this.label);
  final String label;
}

/// Everything of one type, across every batch.
///
/// The batch screens answer "what was shared with this class". This answers "where is that track"
/// — which is the question actually asked mid-lesson, when the batch it came from is exactly the
/// thing you have forgotten.
class MaterialLibraryScreen extends ConsumerStatefulWidget {
  const MaterialLibraryScreen({super.key, required this.fileType});

  final StudyMaterialType fileType;

  @override
  ConsumerState<MaterialLibraryScreen> createState() => _MaterialLibraryScreenState();
}

class _MaterialLibraryScreenState extends ConsumerState<MaterialLibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  LibrarySort _sort = LibrarySort.newest;

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

  List<StudyMaterial> _visible(List<StudyMaterial> all) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? [...all]
        : all
            .where((m) =>
                m.title.toLowerCase().contains(query) ||
                m.fileName.toLowerCase().contains(query))
            .toList();

    filtered.sort((a, b) => switch (_sort) {
          LibrarySort.newest => b.uploadedAt.compareTo(a.uploadedAt),
          LibrarySort.oldest => a.uploadedAt.compareTo(b.uploadedAt),
          LibrarySort.az => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          LibrarySort.za => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        });
    return filtered;
  }

  void _open(List<StudyMaterial> ordered, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FileViewerScreen(material: ordered[index]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.fileType.color(palette);
    final async = ref.watch(materialLibraryProvider(widget.fileType));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette, accent, async.valueOrNull?.length),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.lg),
              child: _searchRow(palette, accent),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4l),
                    child: Text(e.toString().replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: AppType.lg, color: palette.textMuted)),
                  ),
                ),
                data: (all) {
                  final visible = _visible(all);
                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x4l),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.fileType.icon,
                                size: 34, color: palette.textFaint),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              all.isEmpty
                                  ? 'No ${_noun}s have been shared with you yet.'
                                  : 'No ${_noun}s match "$_query".',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppType.lg,
                                  color: palette.textMuted,
                                  height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0,
                        AppSpacing.page, AppSpacing.listBottom),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: MaterialRow(
                        material: visible[i],
                        onTap: () => _open(visible, i),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.fileType != StudyMaterialType.audio
          ? null
          // Playlists only make sense over audio, so the entry point lives on that library alone
          // rather than as a tile everyone sees.
          : Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PlaylistsScreen(),
              )),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4l, vertical: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: AppRadii.all(AppRadii.pill),
                  boxShadow: AppShadows.dropdown,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.queue_music, size: 17, color: palette.onPrimary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Playlists',
                        style: TextStyle(
                            fontSize: AppType.xxl,
                            fontWeight: AppType.bold,
                            color: palette.onPrimary)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _header(AppPalette palette, Color accent, int? count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          AppIconButton(
              icon: Icons.arrow_back, onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title,
                    style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.bold,
                        letterSpacing: AppType.titleTracking,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text(
                  count == null
                      ? 'Across every batch you can see'
                      : '$count $_noun${count == 1 ? '' : 's'} across every batch you can see',
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow(AppPalette palette, Color accent) {
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
                      hintText: 'Search ${_noun}s',
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
        AttachedSelect<LibrarySort>(
          label: 'Sort',
          options: LibrarySort.values,
          labelOf: (s) => s.label,
          value: _sort,
          panelWidth: 200,
          panelSpan: PanelSpan.right,
          onSelected: (s) => setState(() => _sort = s),
          optionBuilder: (context, option, _) => Row(
            children: [
              Expanded(
                child: Text(option.label,
                    style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: option == _sort ? AppType.bold : AppType.regular,
                      color: option == _sort ? accent : palette.text,
                    )),
              ),
              if (option == _sort) Icon(Icons.check, size: 15, color: accent),
            ],
          ),
          triggerBuilder: (context, isOpen, toggle) => Pressable(
            onTap: toggle,
            child: Container(
              height: 38,
              width: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: AppRadii.all(AppRadii.lg),
                border: Border.all(color: isOpen ? accent : palette.border),
              ),
              child: Icon(Icons.swap_vert, size: 16, color: palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

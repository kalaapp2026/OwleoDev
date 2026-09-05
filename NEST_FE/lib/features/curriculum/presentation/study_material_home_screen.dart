import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/curriculum/presentation/batch_material_screen.dart';

enum MaterialBatchSort {
  recent('Recently updated'),
  mostFiles('Most files'),
  az('A - Z'),
  za('Z - A');

  const MaterialBatchSort(this.label);
  final String label;
}

/// Study Material's landing screen: every batch, with how much has been shared with it.
///
/// Organised by batch rather than by course because that is the unit material is actually shared
/// with - a chord chart goes to Batch A, not to everyone taking Guitar.
class StudyMaterialHomeScreen extends ConsumerStatefulWidget {
  const StudyMaterialHomeScreen({super.key});

  @override
  ConsumerState<StudyMaterialHomeScreen> createState() =>
      _StudyMaterialHomeScreenState();
}

class _StudyMaterialHomeScreenState extends ConsumerState<StudyMaterialHomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  MaterialBatchSort _sort = MaterialBatchSort.recent;
  CourseCategory? _categoryFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BatchMaterialSummary> _visible(List<BatchMaterialSummary> all) {
    final q = _query.trim().toLowerCase();
    final filtered = all.where((b) {
      if (_categoryFilter != null && b.courseCategory != _categoryFilter) return false;
      if (q.isEmpty) return true;
      return '${b.batchName} ${b.courseName ?? ''}'.toLowerCase().contains(q);
    }).toList();

    filtered.sort((a, b) {
      // Inactive batches sink regardless of sort - material for a batch that stopped running is
      // rarely what someone is looking for.
      final rank = (a.isActive ? 0 : 1).compareTo(b.isActive ? 0 : 1);
      if (rank != 0) return rank;

      return switch (_sort) {
        MaterialBatchSort.az =>
          a.batchName.toLowerCase().compareTo(b.batchName.toLowerCase()),
        MaterialBatchSort.za =>
          b.batchName.toLowerCase().compareTo(a.batchName.toLowerCase()),
        MaterialBatchSort.mostFiles => b.fileCount.compareTo(a.fileCount),
        // A batch with nothing shared has no date; it sorts last rather than first, which is
        // what comparing nulls as "oldest" would otherwise do.
        MaterialBatchSort.recent => (b.lastUploadedAt ?? DateTime(1970))
            .compareTo(a.lastUploadedAt ?? DateTime(1970)),
      };
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(materialBatchesProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4l),
              child: Text(e.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
            ),
          ),
          data: (batches) {
            final visible = _visible(batches);
            final totalFiles =
                batches.fold<int>(0, (sum, b) => sum + b.fileCount);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(palette, totalFiles, batches.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page, AppSpacing.xxl, AppSpacing.page, 0),
                  child: Column(
                    children: [
                      _searchAndSort(palette),
                      const SizedBox(height: AppSpacing.lg),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _categoryChip(palette),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.x4l),
                            child: Text(
                              batches.isEmpty
                                  ? 'No batches yet. Create one to start sharing material.'
                                  : 'No batches match this search.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppType.lg, color: palette.textFaint),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.xl,
                              AppSpacing.md, AppSpacing.xl, AppSpacing.listBottom),
                          itemCount: visible.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _BatchRow(
                              summary: visible[i],
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) =>
                                      BatchMaterialScreen(summary: visible[i]),
                                ));
                                ref.invalidate(materialBatchesProvider);
                              },
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(AppPalette palette, int totalFiles, int batchCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Study Material',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: AppType.bold,
                  letterSpacing: -0.2,
                  color: palette.text)),
          const SizedBox(height: 2),
          Text(
            '$totalFiles file${totalFiles == 1 ? '' : 's'} across '
            '$batchCount batch${batchCount == 1 ? '' : 'es'}',
            style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
          ),
        ],
      ),
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
                      hintText: 'Search batch or course',
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
        AttachedSelect<MaterialBatchSort>(
          label: 'Sort',
          options: MaterialBatchSort.values,
          labelOf: (s) => s.label,
          value: _sort,
          panelWidth: 220,
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

  Widget _categoryChip(AppPalette palette) {
    final meta = _categoryFilter?.meta(palette);
    return AttachedSelect<CourseCategory?>(
      label: 'Category',
      options: <CourseCategory?>[null, ...CourseCategory.selectable],
      labelOf: (c) => c?.label ?? 'All courses',
      value: _categoryFilter,
      searchable: true,
      searchHint: 'Search category',
      panelWidth: 230,
      onSelected: (c) => setState(() => _categoryFilter = c),
      optionBuilder: (context, option, _) {
        final selected = option == _categoryFilter;
        final dot = option?.meta(palette).color;
        return Row(
          children: [
            if (dot != null) ...[
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: AppSpacing.md),
            ],
            Text(option?.label ?? 'All courses',
                style: TextStyle(
                  fontSize: AppType.xl,
                  fontWeight: selected ? AppType.bold : AppType.regular,
                  color: selected ? (dot ?? palette.primary) : palette.text,
                )),
          ],
        );
      },
      triggerBuilder: (context, isOpen, toggle) => Pressable(
        onTap: toggle,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 7),
          decoration: BoxDecoration(
            color: meta?.soft ?? palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.pill),
            border: Border.all(color: meta?.color ?? palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (meta != null) ...[
                Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Text(_categoryFilter?.label ?? 'All',
                  style: TextStyle(
                    fontSize: AppType.smd,
                    fontWeight: AppType.bold,
                    color: meta?.color ?? palette.textMuted,
                  )),
              Icon(Icons.keyboard_arrow_down,
                  size: 12, color: meta?.color ?? palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.summary, required this.onTap});

  final BatchMaterialSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = summary.courseCategory.meta(palette);

    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: summary.isActive ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.borderSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: meta.soft,
                  borderRadius: AppRadii.all(AppRadii.lg),
                ),
                child: CourseIcon.forCourse(
                  iconKey: summary.courseIconKey,
                  category: summary.courseCategory,
                  color: meta.color,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(summary.batchName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.xxl,
                                fontWeight: AppType.semi,
                                color: summary.isActive
                                    ? palette.text
                                    : palette.textMuted,
                              )),
                        ),
                        if (!summary.isActive) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: palette.surfaceHigh,
                              borderRadius: AppRadii.all(AppRadii.xs),
                              border: Border.all(color: palette.border),
                            ),
                            child: Text('INACTIVE',
                                style: TextStyle(
                                  fontSize: AppType.micro,
                                  fontWeight: AppType.heavy,
                                  letterSpacing: 0.3,
                                  color: palette.textMuted,
                                )),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(summary.courseName ?? 'Unlinked course',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppType.smd,
                            fontWeight: AppType.medium,
                            color: meta.color)),
                    const SizedBox(height: 2),
                    Text(
                      summary.fileCount == 0
                          ? 'No files yet'
                          : '${summary.fileCount} file'
                              '${summary.fileCount == 1 ? '' : 's'}'
                              '${summary.lastUploadedAt == null ? '' : ' · Updated ${formatFeeDate(summary.lastUploadedAt!)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

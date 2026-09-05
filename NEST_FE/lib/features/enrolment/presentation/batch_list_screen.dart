import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/batch_form_screen.dart';

enum BatchSort {
  az('Name (A-Z)'),
  za('Name (Z-A)'),
  course('Course'),
  activeFirst('Active - Inactive'),
  inactiveFirst('Inactive - Active');

  const BatchSort(this.label);
  final String label;
}

/// The three pills beside the category filter. Type and status share a row because they are
/// mutually exclusive in practice - you are either narrowing to a kind of batch or to a state.
enum BatchPill { regular, temporary, inactive }

class BatchListScreen extends ConsumerStatefulWidget {
  const BatchListScreen({super.key});

  @override
  ConsumerState<BatchListScreen> createState() => _BatchListScreenState();
}

class _BatchListScreenState extends ConsumerState<BatchListScreen> {
  final _searchController = TextEditingController();

  String _query = '';
  BatchSort _sort = BatchSort.az;
  CourseCategory? _categoryFilter;
  BatchPill? _pill;
  String? _kebabFor;
  bool _addMenuOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(allBatchesProvider);

  Future<void> _openForm({Batch? existing, BatchType? newType}) async {
    setState(() {
      _kebabFor = null;
      _addMenuOpen = false;
    });
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BatchFormScreen(existing: existing, initialType: newType),
    ));
    if (saved == true) {
      _refresh();
      if (mounted) {
        showAppToast(context, existing == null ? 'Batch created' : 'Batch updated');
      }
    }
  }

  Future<void> _toggleStatus(Batch batch) async {
    setState(() => _kebabFor = null);
    final next = batch.isActive ? 'INACTIVE' : 'ACTIVE';
    try {
      await ref.read(enrolmentApiProvider).setBatchStatus(batch.id, next);
      _refresh();
      if (mounted) {
        showAppToast(context,
            next == 'ACTIVE' ? 'Batch marked active' : 'Batch marked inactive');
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _requestDelete(Batch batch) async {
    setState(() => _kebabFor = null);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete this batch?',
      message: '"${batch.name}" will be permanently removed. This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(enrolmentApiProvider).deleteBatch(batch.id);
      _refresh();
      if (mounted) showAppToast(context, 'Batch deleted');
    } catch (e) {
      // The server refuses when the batch still has students or has held a class. Its message
      // explains which, so it is surfaced verbatim rather than replaced with a generic failure.
      _showError(e);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  List<Batch> _visible(List<Batch> all, Map<String, Course> coursesById) {
    final query = _query.trim().toLowerCase();

    final filtered = all.where((b) {
      final course = coursesById[b.courseId];
      if (_categoryFilter != null && course?.category != _categoryFilter) return false;
      if (_pill == BatchPill.inactive && b.isActive) return false;
      if (_pill == BatchPill.regular && b.isTemporary) return false;
      if (_pill == BatchPill.temporary && !b.isTemporary) return false;
      if (query.isNotEmpty) {
        final haystack = '${b.name} ${course?.name ?? ''}'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sort == BatchSort.inactiveFirst) {
        final rank = (a.isActive ? 1 : 0).compareTo(b.isActive ? 1 : 0);
        if (rank != 0) return rank;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      // Inactive batches sink under every other sort - they are rarely what someone scanning
      // this screen is after.
      final rank = (a.isActive ? 0 : 1).compareTo(b.isActive ? 0 : 1);
      if (rank != 0) return rank;

      if (_sort == BatchSort.course) {
        final byCourse = (coursesById[a.courseId]?.name ?? '')
            .toLowerCase()
            .compareTo((coursesById[b.courseId]?.name ?? '').toLowerCase());
        if (byCourse != 0) return byCourse;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sort == BatchSort.za
          ? b.name.toLowerCase().compareTo(a.name.toLowerCase())
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final batchesAsync = ref.watch(allBatchesProvider);
    final coursesAsync = ref.watch(coursesForFeatureProvider(FeatureKeys.batchCreation));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: batchesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(error: e),
          data: (batches) => coursesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorBody(error: e),
            data: (courses) {
              final coursesById = {for (final c in courses) c.id: c};
              final visible = _visible(batches, coursesById);
              final activeCount = batches.where((b) => b.isActive).length;

              return Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        total: batches.length,
                        active: activeCount,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.page, AppSpacing.xxl, AppSpacing.page, 0),
                        child: Column(
                          children: [
                            _searchAndSortRow(palette),
                            const SizedBox(height: AppSpacing.lg),
                            _filterRow(palette),
                          ],
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            _kebabFor = null;
                            _addMenuOpen = false;
                          }),
                          child: visible.isEmpty
                              ? _EmptyState(hasAny: batches.isNotEmpty)
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl,
                                      AppSpacing.md, AppSpacing.xl, AppSpacing.listBottom + 60),
                                  itemCount: visible.length,
                                  itemBuilder: (context, i) {
                                    final batch = visible[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                      child: _BatchRow(
                                        batch: batch,
                                        course: coursesById[batch.courseId],
                                        kebabOpen: _kebabFor == batch.id,
                                        onTap: () => _openForm(existing: batch),
                                        onToggleKebab: () => setState(() => _kebabFor =
                                            _kebabFor == batch.id ? null : batch.id),
                                        onEdit: () => _openForm(existing: batch),
                                        onToggleStatus: () => _toggleStatus(batch),
                                        onDelete: () => _requestDelete(batch),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                  // Scrim under the expanded add menu, so the choice reads as modal and a stray
                  // tap dismisses rather than hitting a row behind it.
                  if (_addMenuOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _addMenuOpen = false),
                        child: Container(color: const Color(0x73040710)),
                      ),
                    ),
                  if (_addMenuOpen)
                    Positioned(
                      right: AppSpacing.x3l,
                      bottom: AppSpacing.x5l + 66,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _AddTypeButton(
                            label: 'Regular batch',
                            icon: Icons.repeat,
                            accent: palette.primary,
                            onTap: () => _openForm(newType: BatchType.regular),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _AddTypeButton(
                            label: 'Temporary batch',
                            icon: Icons.event_repeat_outlined,
                            accent: palette.gold,
                            onTap: () => _openForm(newType: BatchType.temporary),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    right: AppSpacing.x3l,
                    bottom: AppSpacing.x5l,
                    child: _AddBatchButton(
                      open: _addMenuOpen,
                      onTap: () => setState(() => _addMenuOpen = !_addMenuOpen),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _searchAndSortRow(AppPalette palette) {
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
                    child: Icon(Icons.close_rounded, size: 13, color: palette.textFaint),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AttachedSelect<BatchSort>(
          label: 'Sort',
          options: BatchSort.values,
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
              if (_sort == option) Icon(Icons.check, size: 15, color: palette.primary),
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

  Widget _filterRow(AppPalette palette) {
    final meta = _categoryFilter?.meta(palette);

    Widget pill(BatchPill kind, String label, IconData? icon, Color accent, Color soft) {
      final active = _pill == kind;
      return Expanded(
        child: Pressable(
          // Tapping the active pill clears it, so there's always a way back to "all" without
          // hunting for an All chip that doesn't exist in this row.
          onTap: () => setState(() => _pill = active ? null : kind),
          child: AnimatedContainer(
            duration: AppMotion.fade,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 7),
            decoration: BoxDecoration(
              color: active ? soft : palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: active ? accent : palette.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 11, color: active ? accent : palette.textMuted),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.sm,
                      fontWeight: AppType.bold,
                      color: active ? accent : palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 13,
          child: AttachedSelect<CourseCategory?>(
            label: 'Category',
            // A leading null is the "All batches" entry - modelled as absence rather than a
            // sentinel category so the filter check stays a plain null test.
            options: <CourseCategory?>[null, ...CourseCategory.selectable],
            labelOf: (c) => c?.label ?? 'All batches',
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
                  Text(
                    option?.label ?? 'All batches',
                    style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: selected ? AppType.bold : AppType.regular,
                      color: selected ? (dot ?? palette.primary) : palette.text,
                    ),
                  ),
                ],
              );
            },
            triggerBuilder: (context, isOpen, toggle) => Pressable(
              onTap: toggle,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
                decoration: BoxDecoration(
                  color: meta?.soft ?? palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.pill),
                  border: Border.all(color: meta?.color ?? palette.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (meta != null) ...[
                      Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: meta.color, shape: BoxShape.circle)),
                      const SizedBox(width: AppSpacing.xxs),
                    ],
                    Flexible(
                      child: Text(
                        _categoryFilter?.label ?? 'All',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.smd,
                          fontWeight: AppType.bold,
                          color: meta?.color ?? palette.textMuted,
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down,
                        size: 12, color: meta?.color ?? palette.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        pill(BatchPill.regular, 'Regular', Icons.repeat, palette.primary, palette.primarySoft),
        const SizedBox(width: AppSpacing.xs),
        pill(BatchPill.temporary, 'Temporary', Icons.event_repeat_outlined, palette.gold,
            palette.goldSoft),
        const SizedBox(width: AppSpacing.xs),
        pill(BatchPill.inactive, 'Inactive', null, palette.textFaint, palette.surfaceHigh),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Text(
          error.toString().replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.lg, color: palette.textMuted),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.active, required this.onBack});

  final int total;
  final int active;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: [
          AppIconButton(icon: Icons.arrow_back, onTap: onBack),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Batches',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: AppType.bold,
                        letterSpacing: -0.2,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text('$total batch${total == 1 ? '' : 'es'} · $active active',
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({
    required this.batch,
    required this.course,
    required this.kebabOpen,
    required this.onTap,
    required this.onToggleKebab,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final Batch batch;
  final Course? course;
  final bool kebabOpen;
  final VoidCallback onTap;
  final VoidCallback onToggleKebab;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final category = course?.category ?? CourseCategory.unknown;
    final meta = category.meta(palette);
    final inactive = !batch.isActive;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Opacity(
                  opacity: inactive ? 0.5 : 1,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: meta.soft,
                      borderRadius: AppRadii.all(AppRadii.lg),
                    ),
                    child: CourseIcon.forCourse(
                      iconKey: course?.iconKey,
                      category: category,
                      color: meta.color,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Opacity(
                    opacity: inactive ? 0.5 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                batch.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppType.xxl,
                                  fontWeight: AppType.semi,
                                  color: inactive ? palette.textMuted : palette.text,
                                ),
                              ),
                            ),
                            if (inactive) ...[
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
                        Text.rich(
                          TextSpan(
                            text: course?.name ?? 'Unlinked course',
                            style: TextStyle(
                              fontSize: AppType.smd,
                              fontWeight: AppType.medium,
                              color: meta.color,
                            ),
                            children: [
                              if (batch.trainers.isNotEmpty)
                                TextSpan(
                                  text: ' · ${batch.trainerSummary}',
                                  style: TextStyle(
                                    fontWeight: AppType.regular,
                                    color: palette.textFaint,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '${batch.studentCount} student'
                                '${batch.studentCount == 1 ? '' : 's'}',
                            if (batch.dateRangeSummary != null) batch.dateRangeSummary!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                        ),
                      ],
                    ),
                  ),
                ),
                _Kebab(
                  open: kebabOpen,
                  onToggle: onToggleKebab,
                  batch: batch,
                  onEdit: onEdit,
                  onToggleStatus: onToggleStatus,
                  onDelete: onDelete,
                ),
              ],
            ),
            if (batch.isTemporary)
              Positioned(
                top: -AppSpacing.lg,
                right: 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.gold,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(7),
                      bottomRight: Radius.circular(7),
                    ),
                  ),
                  child: Text('TEMPORARY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: AppType.heavy,
                        letterSpacing: 0.4,
                        color: palette.onGold,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Kebab extends StatelessWidget {
  const _Kebab({
    required this.open,
    required this.onToggle,
    required this.batch,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final bool open;
  final VoidCallback onToggle;
  final Batch batch;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final actions = <(String, bool, VoidCallback)>[
      ('Edit batch', false, onEdit),
      (batch.isActive ? 'Mark as inactive' : 'Mark as active', false, onToggleStatus),
      ('Delete batch', true, onDelete),
    ];

    return AttachedSelect<(String, bool, VoidCallback)>(
      label: '',
      options: actions,
      labelOf: (a) => a.$1,
      isOpen: open,
      onOpenChanged: (_) => onToggle(),
      panelWidth: 190,
      panelSpan: PanelSpan.right,
      onSelected: (a) => a.$3(),
      optionBuilder: (context, option, _) => Text(
        option.$1,
        style: TextStyle(
          fontSize: AppType.lg,
          fontWeight: AppType.regular,
          color: option.$2 ? palette.notPaid : palette.text,
        ),
      ),
      triggerBuilder: (context, isOpen, toggle) =>
          AppIconButton(icon: Icons.more_vert, onTap: toggle, size: 30, iconSize: 15),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAny});
  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Text(
          hasAny
              ? 'No batches match this search.'
              : 'No batches yet. Add your first one below.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
        ),
      ),
    );
  }
}

class _AddTypeButton extends StatelessWidget {
  const _AddTypeButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3l, vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: accent.withValues(alpha: 0.33)),
          boxShadow: AppShadows.dropdown,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: TextStyle(
                    fontSize: AppType.lg,
                    fontWeight: AppType.bold,
                    color: palette.text)),
          ],
        ),
      ),
    );
  }
}

class _AddBatchButton extends StatelessWidget {
  const _AddBatchButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
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
            AnimatedRotation(
              turns: open ? 0.125 : 0,
              duration: AppMotion.chevron,
              child: Icon(Icons.add, size: 17, color: palette.onPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('Add Batch',
                style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: AppType.bold,
                    color: palette.onPrimary)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/curriculum/presentation/course_form_screen.dart';

/// How the list is ordered. Inactive courses sink to the bottom under every option except the
/// one that explicitly asks for the opposite - a deactivated course is almost never what someone
/// scrolling this screen is looking for.
enum CourseSort {
  az('Name (A-Z)'),
  za('Name (Z-A)'),
  activeFirst('Active - Inactive'),
  inactiveFirst('Inactive - Active');

  const CourseSort(this.label);
  final String label;
}

/// The "More" dropdown's contents: the categories that don't get their own chip, plus a status
/// filter. Status sits in the same menu because it competes for the same row of space and is
/// reached the same way, even though it isn't a category.
class _MoreFilter {
  const _MoreFilter.category(this.category) : inactiveOnly = false;
  const _MoreFilter.inactive()
      : category = null,
        inactiveOnly = true;

  final CourseCategory? category;
  final bool inactiveOnly;

  String get label => inactiveOnly ? 'Inactive courses' : category!.label;
}

class CourseListScreen extends ConsumerStatefulWidget {
  const CourseListScreen({super.key});

  @override
  ConsumerState<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends ConsumerState<CourseListScreen> {
  final _searchController = TextEditingController();

  String _query = '';
  CourseSort _sort = CourseSort.az;

  /// null means "All". A category chip and the inactive filter are mutually exclusive - picking
  /// one clears the other, since "Fine Arts" and "Inactive" answer different questions and
  /// combining them silently produces an empty list more often than anything useful.
  CourseCategory? _categoryFilter;
  bool _inactiveOnly = false;

  String? _kebabFor;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(allCoursesProvider);

  Future<void> _openForm({Course? existing}) async {
    setState(() => _kebabFor = null);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CourseFormScreen(existing: existing)),
    );
    if (saved == true) {
      _refresh();
      if (mounted) {
        showAppToast(context, existing == null ? 'Course created' : 'Course updated');
      }
    }
  }

  Future<void> _toggleStatus(Course course) async {
    setState(() => _kebabFor = null);
    final next = course.isActive ? 'INACTIVE' : 'ACTIVE';
    try {
      await ref.read(curriculumApiProvider).setStatus(course.id, next);
      _refresh();
      if (mounted) {
        showAppToast(context,
            next == 'ACTIVE' ? 'Course marked active' : 'Course marked inactive');
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _requestDeactivate(Course course) async {
    setState(() => _kebabFor = null);
    // Not a delete. A course with enrolled students carries fee and attendance history that has
    // to survive, so the destructive-looking action is deactivation - and the dialog says so
    // rather than letting the admin believe they erased something.
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Deactivate this course?',
      message: '"${course.name}" will stop being offered for new enrolment. Students already '
          'enrolled keep their fee and attendance history, and you can reactivate it any time.',
      confirmLabel: 'Deactivate',
    );
    if (confirmed) await _toggleStatus(course);
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  List<Course> _visible(List<Course> all) {
    final query = _query.trim().toLowerCase();

    final filtered = all.where((c) {
      if (_inactiveOnly && c.isActive) return false;
      if (_categoryFilter != null && c.category != _categoryFilter) return false;
      if (query.isNotEmpty && !c.name.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sort == CourseSort.inactiveFirst) {
        final rank = (a.isActive ? 1 : 0).compareTo(b.isActive ? 1 : 0);
        if (rank != 0) return rank;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      final rank = (a.isActive ? 0 : 1).compareTo(b.isActive ? 0 : 1);
      if (rank != 0) return rank;
      return _sort == CourseSort.za
          ? b.name.toLowerCase().compareTo(a.name.toLowerCase())
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(allCoursesProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
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
            final visible = _visible(all);
            final activeCount = all.where((c) => c.isActive).length;

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      total: all.length,
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
                          _filterChipRow(palette),
                        ],
                      ),
                    ),
                    Expanded(
                      // Tapping anywhere off an open kebab closes it, which is the only way to
                      // dismiss it without picking one of its actions.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _kebabFor = null),
                        child: visible.isEmpty
                            ? _EmptyState(hasAnyCourses: all.isNotEmpty)
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(AppSpacing.xl,
                                    AppSpacing.md, AppSpacing.xl, AppSpacing.listBottom + 40),
                                itemCount: visible.length,
                                itemBuilder: (context, i) {
                                  final course = visible[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: _CourseRow(
                                      course: course,
                                      kebabOpen: _kebabFor == course.id,
                                      onTap: () => _openForm(existing: course),
                                      onToggleKebab: () => setState(() =>
                                          _kebabFor = _kebabFor == course.id ? null : course.id),
                                      onEdit: () => _openForm(existing: course),
                                      onToggleStatus: () => _toggleStatus(course),
                                      onDeactivate: () => _requestDeactivate(course),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: AppSpacing.x3l,
                  bottom: AppSpacing.x5l,
                  child: _AddCourseButton(onTap: () => _openForm()),
                ),
              ],
            );
          },
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
                      color: palette.text,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Search course',
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
        AttachedSelect<CourseSort>(
          label: 'Sort',
          options: CourseSort.values,
          labelOf: (s) => s.label,
          value: _sort,
          panelWidth: 220,
          panelSpan: PanelSpan.right,
          onSelected: (s) => setState(() => _sort = s),
          optionBuilder: (context, option, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                option.label,
                style: TextStyle(
                  fontSize: AppType.xl,
                  fontWeight: _sort == option ? AppType.bold : AppType.regular,
                  color: _sort == option ? palette.primary : palette.text,
                ),
              ),
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

  Widget _filterChipRow(AppPalette palette) {
    final moreOptions = <_MoreFilter>[
      for (final c in CourseCategory.more) _MoreFilter.category(c),
      const _MoreFilter.inactive(),
    ];

    // The "More" chip adopts the appearance of whatever is selected inside it, so a filter chosen
    // from the dropdown is still visibly active without the chip row growing.
    final moreSelected = _inactiveOnly ||
        (_categoryFilter != null && CourseCategory.more.contains(_categoryFilter));
    final moreMeta = _inactiveOnly
        ? CategoryMeta(color: palette.textFaint, soft: palette.surfaceHigh, dim: palette.textFaint)
        : (moreSelected ? _categoryFilter!.meta(palette) : null);
    final moreLabel = _inactiveOnly
        ? 'Inactive'
        : (moreSelected ? _categoryFilter!.label : 'More');

    return Row(
      children: [
        _CategoryChip(
          label: 'All',
          selected: _categoryFilter == null && !_inactiveOnly,
          accent: palette.primary,
          soft: palette.primarySoft,
          showDot: false,
          onTap: () => setState(() {
            _categoryFilter = null;
            _inactiveOnly = false;
          }),
        ),
        for (final category in CourseCategory.primary) ...[
          const SizedBox(width: AppSpacing.sm),
          Builder(builder: (context) {
            final meta = category.meta(palette);
            return _CategoryChip(
              label: category.label,
              selected: _categoryFilter == category && !_inactiveOnly,
              accent: meta.color,
              soft: meta.soft,
              showDot: true,
              onTap: () => setState(() {
                _categoryFilter = category;
                _inactiveOnly = false;
              }),
            );
          }),
        ],
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AttachedSelect<_MoreFilter>(
            label: 'More',
            options: moreOptions,
            labelOf: (o) => o.label,
            searchable: true,
            searchHint: 'Search category',
            panelWidth: 210,
            panelSpan: PanelSpan.right,
            onSelected: (o) => setState(() {
              _categoryFilter = o.category;
              _inactiveOnly = o.inactiveOnly;
            }),
            optionBuilder: (context, option, _) {
              final dot = option.inactiveOnly
                  ? palette.textFaint
                  : option.category!.meta(palette).color;
              final selected = option.inactiveOnly
                  ? _inactiveOnly
                  : (!_inactiveOnly && _categoryFilter == option.category);
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: selected ? AppType.bold : AppType.regular,
                      color: selected ? dot : palette.text,
                    ),
                  ),
                ],
              );
            },
            triggerBuilder: (context, isOpen, toggle) => _CategoryChip(
              label: moreLabel,
              selected: moreSelected,
              accent: moreMeta?.color ?? palette.textMuted,
              soft: moreMeta?.soft ?? palette.surfaceRaised,
              showDot: moreMeta != null,
              showChevron: true,
              onTap: toggle,
            ),
          ),
        ),
      ],
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.borderSoft)),
      ),
      child: Row(
        children: [
          AppIconButton(icon: Icons.arrow_back, onTap: onBack),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Courses',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: AppType.bold,
                    letterSpacing: -0.2,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$total course${total == 1 ? '' : 's'} · $active active',
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.soft,
    required this.showDot,
    required this.onTap,
    this.showChevron = false,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color soft;
  final bool showDot;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? soft : palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          border: Border.all(color: selected ? accent : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.base,
                  fontWeight: AppType.bold,
                  color: selected ? accent : palette.textMuted,
                ),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down,
                  size: 13, color: selected ? accent : palette.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.course,
    required this.kebabOpen,
    required this.onTap,
    required this.onToggleKebab,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDeactivate,
  });

  final Course course;
  final bool kebabOpen;
  final VoidCallback onTap;
  final VoidCallback onToggleKebab;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = course.category.meta(palette);
    final inactive = !course.isActive;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Row(
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
                  iconKey: course.iconKey,
                  category: course.category,
                  color: meta.color,
                  size: 18,
                ),
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
                        child: Text(
                          course.name,
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
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: palette.goldSoft,
                            borderRadius: AppRadii.all(AppRadii.xs),
                            border: Border.all(color: palette.gold),
                          ),
                          child: Text(
                            'INACTIVE',
                            style: TextStyle(
                              fontSize: AppType.micro,
                              fontWeight: AppType.heavy,
                              letterSpacing: 0.3,
                              color: palette.gold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Opacity(
                    opacity: inactive ? 0.8 : 1,
                    child: Text(
                      '${course.category.label} · ${course.feeSummary}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppType.smd, color: palette.textFaint),
                    ),
                  ),
                ],
              ),
            ),
            _Kebab(
              open: kebabOpen,
              onToggle: onToggleKebab,
              course: course,
              onEdit: onEdit,
              onToggleStatus: onToggleStatus,
              onDeactivate: onDeactivate,
            ),
          ],
        ),
      ),
    );
  }
}

/// The row's overflow menu. Uses [AttachedSelect]'s anchoring so it opens under the button and
/// above every following row, rather than being clipped by the list.
class _Kebab extends StatelessWidget {
  const _Kebab({
    required this.open,
    required this.onToggle,
    required this.course,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDeactivate,
  });

  final bool open;
  final VoidCallback onToggle;
  final Course course;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final actions = <(String, bool, VoidCallback)>[
      ('Edit course', false, onEdit),
      (course.isActive ? 'Mark as inactive' : 'Mark as active', false, onToggleStatus),
      // Only offered while active - "deactivate" on an already-inactive course is a no-op that
      // still shows a confirmation dialog, which reads as a bug.
      if (course.isActive) ('Deactivate course', true, onDeactivate),
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
      triggerBuilder: (context, isOpen, toggle) => AppIconButton(
        icon: Icons.more_vert,
        onTap: toggle,
        size: 30,
        iconSize: 15,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyCourses});

  final bool hasAnyCourses;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Text(
          hasAnyCourses
              ? 'No courses match this search.'
              : 'No courses yet. Add your first one below.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
        ),
      ),
    );
  }
}

class _AddCourseButton extends StatelessWidget {
  const _AddCourseButton({required this.onTap});

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
            Icon(Icons.add, size: 17, color: palette.onPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Add Course',
              style: TextStyle(
                fontSize: AppType.xxl,
                fontWeight: AppType.bold,
                color: palette.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/flip_toggle.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/data/user_tab.dart';
import 'package:nest_fe/features/enrolment/presentation/user_form_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/widgets/user_dialogs.dart';

enum UserSort {
  az('Name (A-Z)'),
  za('Name (Z-A)'),
  activeFirst('Active - Inactive'),
  inactiveFirst('Inactive - Active');

  const UserSort(this.label);
  final String label;
}

/// Management rosters - `includeInactive: true`, unlike the batch pickers' active-only providers,
/// because an admin here needs to see a deactivated person in order to reactivate them.
final courseStudentsManageProvider =
    FutureProvider.autoDispose.family<List<StudentSummary>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).studentsForCourse(courseId, includeInactive: true);
});

final courseTrainersManageProvider =
    FutureProvider.autoDispose.family<List<TrainerSummary>, String>((ref, courseId) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(enrolmentApiProvider).trainersForCourse(courseId, includeInactive: true);
});

/// One roster row, flattened from either summary type so the list does not need two near-identical
/// branches for what renders identically.
class _Person {
  const _Person({
    required this.membershipId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.active,
  });

  final String membershipId;
  final String userId;
  final String username;
  final String fullName;
  final bool active;
}

/// The Students / Trainers roster. Course-scoped, because an academy-wide list of every person is
/// not something anyone actually looks for - the question is always "who is on this course".
class UserListScreen extends ConsumerStatefulWidget {
  const UserListScreen({super.key});

  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends ConsumerState<UserListScreen> {
  final _searchController = TextEditingController();

  UserTab _tab = UserTab.student;
  UserSort _sort = UserSort.az;
  String _query = '';
  String? _courseId;
  String? _kebabFor;

  late final bool _canAddStudents;
  late final bool _canAddTrainers;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionControllerProvider).user;
    final isAdmin = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
    // Mirrors the ERP tile's anyOf(student, trainer) rule: someone holding only one of the two
    // must not be offered a tab they would get a 403 on.
    _canAddStudents = isAdmin || (user?.hasFeature(FeatureKeys.studentRegistration) ?? false);
    _canAddTrainers = isAdmin || (user?.hasFeature(FeatureKeys.trainerRegistration) ?? false);
    if (!_canAddStudents && _canAddTrainers) _tab = UserTab.trainer;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _accent(AppPalette palette) =>
      _tab == UserTab.student ? palette.primary : palette.gold;

  void _refresh() {
    final courseId = _courseId;
    if (courseId == null) return;
    ref.invalidate(courseStudentsManageProvider(courseId));
    ref.invalidate(courseTrainersManageProvider(courseId));
    ref.invalidate(studentsForCourseProvider(courseId));
    ref.invalidate(trainersForCourseProvider(courseId));
  }

  Future<void> _openForm({_Person? existing}) async {
    setState(() => _kebabFor = null);
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => UserFormScreen(
        tab: _tab,
        editingMembershipId: existing?.membershipId,
        editingName: existing?.fullName,
        initialCourseId: _courseId,
      ),
    ));
    if (saved == true) _refresh();
  }

  Future<void> _toggleStatus(_Person person) async {
    setState(() => _kebabFor = null);
    final courseId = _courseId;
    if (courseId == null) return;
    try {
      await ref
          .read(enrolmentApiProvider)
          .setCourseMemberActive(courseId, person.membershipId, !person.active);
      _refresh();
      if (mounted) {
        showAppToast(context,
            person.active ? '${person.fullName} marked inactive.' : '${person.fullName} marked active.');
      }
    } catch (e) {
      if (mounted) showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _resetCredentials(_Person person) async {
    setState(() => _kebabFor = null);
    try {
      final temp = await ref.read(enrolmentApiProvider).resetStudentPassword(person.membershipId);
      if (!mounted) return;
      await showCredentialsHandoff(
        context,
        fullName: person.fullName,
        username: person.username,
        temporaryPassword: temp,
        title: 'New password',
      );
    } catch (e) {
      if (mounted) showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Removing someone from a course is what "delete" means here - the account itself belongs to
  /// the person, not to this academy, and may be in use at another one.
  Future<void> _requestRemove(_Person person) async {
    setState(() => _kebabFor = null);
    final courseId = _courseId;
    if (courseId == null) return;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Remove from this course?',
      message: '${person.fullName} will drop off this course\'s lists. Their NEST account and '
          'their place on any other course stay as they are.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await ref.read(enrolmentApiProvider).setCourseMemberActive(courseId, person.membershipId, false);
      _refresh();
      if (mounted) showAppToast(context, '${person.fullName} removed from this course.');
    } catch (e) {
      if (mounted) showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<_Person> _visible(List<_Person> people) {
    final query = _query.trim().toLowerCase();
    final filtered = people.where((p) {
      if (query.isEmpty) return true;
      return p.fullName.toLowerCase().contains(query) ||
          p.username.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      // Inactive people sink to the bottom in every sort but the one that explicitly asks for
      // the opposite - they are the exception on the roster, not the thing being looked for.
      final aRank = a.active ? 0 : 1;
      final bRank = b.active ? 0 : 1;
      if (aRank != bRank) {
        return _sort == UserSort.inactiveFirst ? bRank - aRank : aRank - bRank;
      }
      return _sort == UserSort.za
          ? b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase())
          : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = _accent(palette);
    // Scoped to the feature behind the visible tab, so a trainer who may register students on one
    // course does not get a course picker listing the whole academy.
    final coursesAsync = ref.watch(coursesForFeatureProvider(
        _tab == UserTab.student ? FeatureKeys.studentRegistration : FeatureKeys.trainerRegistration));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(palette),
                _tabs(palette, accent),
                coursesAsync.when(
                  loading: () => const Expanded(
                      child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Expanded(child: _errorBody(palette, e)),
                  data: (courses) {
                    if (courses.isEmpty) {
                      return Expanded(
                        child: _emptyBody(palette,
                            'No courses yet. Create one before registering anyone against it.'),
                      );
                    }
                    // An unset picker would leave the screen showing nothing, which reads as
                    // broken rather than as "make a choice".
                    _courseId ??= courses.first.id;
                    final course = courses.firstWhere((c) => c.id == _courseId,
                        orElse: () => courses.first);

                    return Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
                            child: Column(
                              children: [
                                _searchRow(palette, accent),
                                const SizedBox(height: AppSpacing.xl),
                                _coursePicker(palette, accent, courses, course),
                                const SizedBox(height: AppSpacing.xl),
                              ],
                            ),
                          ),
                          Expanded(child: _roster(palette, course)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            if (_canAddStudents || _canAddTrainers)
              Positioned(
                right: AppSpacing.x3l,
                bottom: AppSpacing.x5l,
                child: FlipToggle(
                  isOn: _tab == UserTab.student,
                  onLabel: 'Add student',
                  offLabel: 'Add trainer',
                  onIcon: Icons.person_add_alt,
                  offIcon: Icons.badge_outlined,
                  onColor: palette.primary,
                  offColor: palette.gold,
                  width: 158,
                  height: 46,
                  onTap: (_tab == UserTab.student ? _canAddStudents : _canAddTrainers)
                      ? () => _openForm()
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.xxl),
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
                Text('Users',
                    style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppType.bold,
                        letterSpacing: AppType.titleTracking,
                        color: palette.text)),
                const SizedBox(height: 2),
                Text('Students and trainers at this academy',
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Underlined tabs rather than a segmented pill: the tab switches which *population* is on
  /// screen, and the underline reads as navigation where a filled pill would read as a filter.
  Widget _tabs(AppPalette palette, Color accent) {
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
      child: Row(
        children: UserTab.values.map((tab) {
          final selected = tab == _tab;
          return Expanded(
            child: Pressable(
              onTap: () => setState(() {
                _tab = tab;
                _kebabFor = null;
                _query = '';
                _searchController.clear();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? (tab == UserTab.student ? palette.primary : palette.gold)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: selected ? AppType.bold : AppType.medium,
                    color: selected ? accent : palette.textMuted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
                      hintText: 'Search ${_tab.label.toLowerCase()}',
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
        AttachedSelect<UserSort>(
          label: 'Sort',
          options: UserSort.values,
          labelOf: (s) => s.label,
          value: _sort,
          panelWidth: 210,
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

  /// The course picker carries a floating label in the accent colour - it is the one required
  /// choice on the screen, and a plain filled field would let it pass for another filter.
  Widget _coursePicker(
      AppPalette palette, Color accent, List<Course> courses, Course course) {
    return AttachedSelect<Course>(
      label: 'Course',
      options: courses,
      labelOf: (c) => c.name,
      value: course,
      searchable: true,
      searchHint: 'Search course',
      onSelected: (c) => setState(() {
        _courseId = c.id;
        _kebabFor = null;
      }),
      optionBuilder: (context, option, _) {
        final meta = option.category.meta(palette);
        final selected = option.id == _courseId;
        return Row(
          children: [
            Container(
              height: 9,
              width: 9,
              decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.xl,
                    fontWeight: selected ? AppType.bold : AppType.regular,
                    color: selected ? meta.color : palette.text,
                  )),
            ),
          ],
        );
      },
      triggerBuilder: (context, isOpen, toggle) => Stack(
        clipBehavior: Clip.none,
        children: [
          Pressable(
            onTap: toggle,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                borderRadius: AppRadii.all(AppRadii.xl),
                border: Border.all(color: accent, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_outlined, size: 17, color: accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(course.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppType.x3l,
                            fontWeight: AppType.bold,
                            color: palette.text)),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: AppMotion.chevron,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: accent),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -7,
            left: AppSpacing.lg,
            child: Container(
              color: palette.bg,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text('Course (required)',
                  style: TextStyle(
                      fontSize: AppType.xs,
                      fontWeight: AppType.bold,
                      letterSpacing: 0.3,
                      color: accent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roster(AppPalette palette, Course course) {
    if (_tab == UserTab.student) {
      final async = ref.watch(courseStudentsManageProvider(course.id));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorBody(palette, e),
        data: (students) => _rosterList(
          palette,
          course,
          students
              .map((s) => _Person(
                    membershipId: s.membershipId,
                    userId: s.userId,
                    username: s.username,
                    fullName: s.fullName,
                    active: s.active,
                  ))
              .toList(),
        ),
      );
    }
    final async = ref.watch(courseTrainersManageProvider(course.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _errorBody(palette, e),
      data: (trainers) => _rosterList(
        palette,
        course,
        trainers
            .map((t) => _Person(
                  membershipId: t.membershipId,
                  userId: t.userId,
                  username: t.username,
                  fullName: t.fullName,
                  active: t.active,
                ))
            .toList(),
      ),
    );
  }

  Widget _rosterList(AppPalette palette, Course course, List<_Person> people) {
    final visible = _visible(people);
    if (visible.isEmpty) {
      return _emptyBody(
        palette,
        people.isEmpty
            ? 'No ${_tab.label.toLowerCase()} on ${course.name} yet.'
            : 'No ${_tab.label.toLowerCase()} match "$_query".',
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _kebabFor = null),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 0, AppSpacing.page, AppSpacing.listBottom),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final person = visible[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _PersonRow(
              person: person,
              accent: _accent(palette),
              roleNoun: _tab.noun,
              kebabOpen: _kebabFor == person.membershipId,
              onTap: () => _openForm(existing: person),
              onToggleKebab: () => setState(() => _kebabFor =
                  _kebabFor == person.membershipId ? null : person.membershipId),
              onEdit: () => _openForm(existing: person),
              onResetCredentials: () => _resetCredentials(person),
              onToggleStatus: () => _toggleStatus(person),
              onRemove: () => _requestRemove(person),
            ),
          );
        },
      ),
    );
  }

  Widget _errorBody(AppPalette palette, Object error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Text(error.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
        ),
      );

  Widget _emptyBody(AppPalette palette, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 34, color: palette.textFaint),
              const SizedBox(height: AppSpacing.lg),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: AppType.lg, color: palette.textMuted, height: 1.5)),
            ],
          ),
        ),
      );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.accent,
    required this.roleNoun,
    required this.kebabOpen,
    required this.onTap,
    required this.onToggleKebab,
    required this.onEdit,
    required this.onResetCredentials,
    required this.onToggleStatus,
    required this.onRemove,
  });

  final _Person person;
  final Color accent;
  final String roleNoun;
  final bool kebabOpen;
  final VoidCallback onTap;
  final VoidCallback onToggleKebab;
  final VoidCallback onEdit;
  final VoidCallback onResetCredentials;
  final VoidCallback onToggleStatus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
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
                  opacity: person.active ? 1 : 0.6,
                  child: Row(
                    children: [
                      PersonAvatar(
                          name: person.fullName, seed: person.userId, size: 40),
                      const SizedBox(width: AppSpacing.lg),
                    ],
                  ),
                ),
                Expanded(
                  child: Opacity(
                    opacity: person.active ? 1 : 0.6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(person.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: AppType.x3l,
                                fontWeight: AppType.bold,
                                color: palette.text)),
                        const SizedBox(height: 2),
                        Text('@${person.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: AppType.base, color: palette.textFaint)),
                      ],
                    ),
                  ),
                ),
                if (!person.active) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: palette.goldSoft,
                      borderRadius: AppRadii.all(AppRadii.xs),
                      border: Border.all(color: palette.gold),
                    ),
                    child: Text('INACTIVE',
                        style: TextStyle(
                            fontSize: AppType.micro,
                            fontWeight: AppType.heavy,
                            letterSpacing: 0.3,
                            color: palette.gold)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Pressable(
                  onTap: onToggleKebab,
                  child: Container(
                    height: 30,
                    width: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kebabOpen ? palette.surfaceHigh : Colors.transparent,
                      borderRadius: AppRadii.all(AppRadii.smd),
                    ),
                    child: Icon(Icons.more_vert, size: 15, color: palette.textMuted),
                  ),
                ),
              ],
            ),
            if (kebabOpen)
              Positioned(
                top: 34,
                right: 0,
                child: _KebabMenu(
                  roleNoun: roleNoun,
                  active: person.active,
                  onEdit: onEdit,
                  onResetCredentials: onResetCredentials,
                  onToggleStatus: onToggleStatus,
                  onRemove: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KebabMenu extends StatelessWidget {
  const _KebabMenu({
    required this.roleNoun,
    required this.active,
    required this.onEdit,
    required this.onResetCredentials,
    required this.onToggleStatus,
    required this.onRemove,
  });

  final String roleNoun;
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onResetCredentials;
  final VoidCallback onToggleStatus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = <({String label, VoidCallback onTap, bool danger})>[
      (label: 'Edit $roleNoun', onTap: onEdit, danger: false),
      (label: 'Reset credentials', onTap: onResetCredentials, danger: false),
      (
        label: active ? 'Mark as inactive' : 'Mark as active',
        onTap: onToggleStatus,
        danger: false
      ),
      (label: 'Remove from course', onTap: onRemove, danger: true),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 196,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
          boxShadow: AppShadows.dropdown,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              Pressable(
                onTap: items[i].onTap,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                  decoration: BoxDecoration(
                    border: i < items.length - 1
                        ? Border(bottom: BorderSide(color: palette.borderSoft))
                        : null,
                  ),
                  child: Text(items[i].label,
                      style: TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppType.regular,
                        color: items[i].danger ? palette.notPaid : palette.text,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

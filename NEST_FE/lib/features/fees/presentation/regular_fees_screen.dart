import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/other_fees_screen.dart';
import 'package:nest_fe/features/fees/presentation/student_profile_screen.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart'
    show FeesScreen, feesApiProvider;
import 'package:nest_fe/features/fees/presentation/widgets/student_list_body.dart';

/// Which selector currently owns the open dropdown panel.
///
/// Only one may be open at a time: the panels are anchored under their triggers and would
/// otherwise stack over each other and the list below.
enum _OpenPanel { none, course, batch }

/// The roster request: the three things that identify a batch's fees for a month.
///
/// A record, so Riverpod's family caches on value equality - re-selecting the same course and
/// batch reuses the fetch instead of re-issuing it.
typedef _RosterKey = ({String courseId, String batchId, String period});

final _rosterProvider =
    FutureProvider.autoDispose.family<FeeRoster, _RosterKey>((ref, key) {
  return ref.watch(feesApiProvider).roster(
        courseId: key.courseId,
        batchId: key.batchId,
        period: key.period,
      );
});

/// Regular Fees: month -> course -> batch, then the batch's students.
///
/// The list appears as soon as course and batch are both chosen - there is no "view" button,
/// because nothing is left to confirm once the cascade is complete.
class RegularFeesScreen extends ConsumerStatefulWidget {
  const RegularFeesScreen({super.key});

  @override
  ConsumerState<RegularFeesScreen> createState() => _RegularFeesScreenState();
}

class _RegularFeesScreenState extends ConsumerState<RegularFeesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _courseId;
  String? _courseName;
  String? _batchId;
  String? _batchName;
  _OpenPanel _open = _OpenPanel.none;

  /// Collapses the selector block once the student list is scrolled, giving the list the screen.
  /// It comes back as soon as the list returns near the top.
  bool _selectorsVisible = true;
  bool _busy = false;

  String get _period => periodOf(_month);

  _RosterKey? get _rosterKey => (_courseId != null && _batchId != null)
      ? (courseId: _courseId!, batchId: _batchId!, period: _period)
      : null;

  DateTime get _thisMonth => DateTime(DateTime.now().year, DateTime.now().month);

  void _setMonth(DateTime month) {
    setState(() {
      _month = DateTime(month.year, month.month);
      _selectorsVisible = true;
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showAppCalendar(
      context: context,
      month: _month,
      // Never past the current month: fees for a month that has not started are not collectable.
      latestMonth: _thisMonth,
    );
    if (picked != null) _setMonth(picked);
  }

  void _selectCourse(dynamic course) {
    setState(() {
      _courseId = course.id as String;
      _courseName = course.name as String;
      // The chosen batch belonged to the previous course, so it cannot survive the change.
      // Leaving it would silently request a roster for a pair that does not exist.
      _batchId = null;
      _batchName = null;
    });
  }

  Future<void> _markPaid(FeeRosterEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).recordEntry(
            membershipId: entry.membershipId,
            courseId: _courseId!,
            period: _period,
            amountPaid: entry.balance,
            mode: 'CASH',
          );
      _refresh();
      if (mounted) showAppToast(context, '${entry.studentName} marked as Paid');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(FeeRosterEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).reverseEntry(transactionId: entry.lastPaymentId!);
      _refresh();
      if (mounted) showAppToast(context, '${entry.studentName} reverted to Not Paid');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The profile can change what is owed - a payment, or an edited agreed fee - so the roster is
  /// refreshed on return rather than left showing a figure the student's own screen contradicts.
  Future<void> _openProfile(FeeRosterEntry entry) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StudentProfileScreen(
        membershipId: entry.membershipId,
        period: _period,
      ),
    ));
    _refresh();
  }

  void _refresh() {
    final key = _rosterKey;
    if (key != null) ref.invalidate(_rosterProvider(key));
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coursesAsync = ref.watch(activeCoursesProvider);
    final key = _rosterKey;
    final context_ = _courseName != null && _batchName != null
        ? '$_courseName · $_batchName'
        : 'Select month, course & batch';

    // No own Scaffold or AppBar - this renders inside AppShell's IndexedStack as the Fees tab,
    // which already supplies both.
    return ColoredBox(
      color: palette.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context_,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
                  ),
                ),
                // The report download, fee slips and per-student history still live on the old
                // screen - they are a later phase of this port. Keeping a door to them means the
                // redesign doesn't take working features away in the meantime.
                Pressable(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const OtherFeesScreen(),
                  )),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_outlined, size: 13, color: palette.gateway),
                      const SizedBox(width: AppSpacing.xxs),
                      Text('Other Fees',
                          style: TextStyle(
                              fontSize: AppType.xs,
                              fontWeight: AppType.bold,
                              color: palette.gateway)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Pressable(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _LegacyFeesPage(),
                  )),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined, size: 13, color: palette.textMuted),
                      const SizedBox(width: AppSpacing.xxs),
                      Text('Reports',
                          style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The selector block collapses rather than unmounting, so the chosen course and batch
          // survive the scroll and come straight back.
          AnimatedSize(
            duration: AppMotion.collapse,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: _selectorsVisible
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xs),
                    child: Column(
                      children: [
                        _MonthStepper(
                          month: _month,
                          onPrevious: () =>
                              _setMonth(DateTime(_month.year, _month.month - 1)),
                          onNext: _month.isBefore(_thisMonth)
                              ? () => _setMonth(DateTime(_month.year, _month.month + 1))
                              : null,
                          onPickDate: _pickMonth,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        coursesAsync.when(
                          loading: () => const _SelectorPlaceholder(),
                          error: (e, _) =>
                              _InlineError(message: 'Courses failed to load', error: e),
                          data: (courses) => AttachedSelect<dynamic>(
                            label: 'Course',
                            placeholder: 'Select course',
                            options: courses,
                            labelOf: (c) => c.name as String,
                            value: courses.where((c) => c.id == _courseId).firstOrNull,
                            searchable: courses.length > 6,
                            isOpen: _open == _OpenPanel.course,
                            onOpenChanged: (o) => setState(
                                () => _open = o ? _OpenPanel.course : _OpenPanel.none),
                            onSelected: _selectCourse,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _BatchSelect(
                          courseId: _courseId,
                          batchId: _batchId,
                          isOpen: _open == _OpenPanel.batch,
                          onOpenChanged: (o) =>
                              setState(() => _open = o ? _OpenPanel.batch : _OpenPanel.none),
                          onSelected: (b) => setState(() {
                            _batchId = b.id;
                            _batchName = b.name;
                          }),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (key == null)
            Expanded(
              child: _EmptyState(
                icon: Icons.groups_outlined,
                message: 'Select a course and batch above\nto see the student list',
              ),
            )
          else
            Expanded(
              child: ref.watch(_rosterProvider(key)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        _InlineError(message: 'Could not load the roster', error: e),
                    data: (roster) => StudentListBody(
                      roster: roster,
                      busy: _busy,
                      emptyText: 'No students in this batch yet.',
                      onMarkPaid: _markPaid,
                      onUndo: _undo,
                      onOpenProfile: _openProfile,
                      onScrolled: (scrolled) =>
                          setState(() => _selectorsVisible = !scrolled),
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

/// The batch half of the cascade. Locked until a course is chosen - a padlock rather than a
/// greyed control, because the reason is "decide the course first", not "unavailable to you".
class _BatchSelect extends ConsumerWidget {
  const _BatchSelect({
    required this.courseId,
    required this.batchId,
    required this.isOpen,
    required this.onOpenChanged,
    required this.onSelected,
  });

  final String? courseId;
  final String? batchId;
  final bool isOpen;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<Batch> onSelected;

  AttachedSelect<Batch> _placeholder(String text, {bool locked = false}) => AttachedSelect<Batch>(
        label: 'Batch',
        options: const [],
        labelOf: (b) => b.name,
        enabled: false,
        locked: locked,
        placeholder: text,
        onSelected: (_) {},
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (courseId == null) {
      return _placeholder('Select a course first', locked: true);
    }

    return ref.watch(batchesForCourseProvider(courseId!)).when(
          loading: () => _placeholder('Loading...'),
          error: (_, _) => _placeholder('Unavailable'),
          data: (batches) {
            final active = batches.where((b) => b.status == 'ACTIVE').toList();
            return AttachedSelect<Batch>(
              label: 'Batch',
              placeholder: 'Select batch',
              options: active,
              labelOf: (b) => b.name,
              value: active.where((b) => b.id == batchId).firstOrNull,
              searchable: active.length > 6,
              isOpen: isOpen,
              onOpenChanged: onOpenChanged,
              emptyLabel: 'No active batches',
              onSelected: onSelected,
            );
          },
        );
  }
}

/// Month stepper with the month itself opening a calendar, matching the prototype's control.
class _MonthStepper extends StatelessWidget {
  const _MonthStepper({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
  });

  final DateTime month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.chevron_left_rounded, onTap: onPrevious),
          Expanded(
            child: Pressable(
              onTap: onPickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 14, color: palette.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      monthLabel(month),
                      style: TextStyle(
                        fontSize: AppType.xxl,
                        fontWeight: AppType.bold,
                        color: palette.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _StepButton(icon: Icons.chevron_right_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: onTap == null ? palette.textFaint : palette.text),
      ),
    );
  }
}

class _SelectorPlaceholder extends StatelessWidget {
  const _SelectorPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: palette.textFaint),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.lg, color: palette.textFaint, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.error});

  final String message;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 30, color: palette.notPaid),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                style: TextStyle(
                    fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              error.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pre-redesign fees screen, still carrying the report download, fee slips and per-student
/// history that later phases will absorb. It renders as a tab body with no chrome of its own, so
/// it needs a Scaffold when pushed as a page.
class _LegacyFeesPage extends StatelessWidget {
  const _LegacyFeesPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & history')),
      body: const FeesScreen(),
    );
  }
}

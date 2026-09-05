import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/scheduling/presentation/recurring_change_screen.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/schedule_action_sheets.dart';
import 'package:nest_fe/features/scheduling/presentation/widgets/schedule_row.dart';

/// Everything about one class, with the same actions as the feed row's kebab laid out as
/// full-width rows.
///
/// Pops `true` when something changed, so the caller knows to refetch. The entry it was opened
/// with is a snapshot - after an action the screen closes rather than trying to patch itself,
/// because most of these actions change which row this even is.
class ClassDetailScreen extends ConsumerStatefulWidget {
  const ClassDetailScreen({super.key, required this.entry});

  final ScheduleEntry entry;

  @override
  ConsumerState<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends ConsumerState<ClassDetailScreen> {
  bool _busy = false;

  ScheduleEntry get entry => widget.entry;

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _run(Future<void> Function() call, String message) async {
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) {
        showAppToast(context, message);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handle(ScheduleAction action) async {
    if (_busy) return;
    final api = ref.read(schedulingApiProvider);

    switch (action) {
      case ScheduleAction.reschedule:
        final outcome = await showRescheduleSheet(context: context, entry: entry);
        if (outcome == null || !mounted) return;
        await _run(
          () => api.reschedule(
            classInstanceId: entry.classInstanceId,
            newDate: SchedulingApi.isoDate(outcome.newDate),
            newStartTime: outcome.newStartTime.wire,
            newEndTime: outcome.newEndTime.wire,
            reason: outcome.reason,
          ),
          'Class moved to ${formatFeeDate(outcome.newDate)}',
        );

      case ScheduleAction.cancel:
        final reason = await showCancelClassSheet(context: context, entry: entry);
        if (reason == null || !mounted) return;
        await _run(
          () => api.cancelClass(
              classInstanceId: entry.classInstanceId, reason: reason),
          'Class cancelled',
        );

      case ScheduleAction.swap:
        if (entry.courseId == null) return;
        final trainers =
            await ref.read(trainersForCourseProvider(entry.courseId!).future);
        if (!mounted) return;
        final substituteId = await showSwapInstructorSheet(
          context: context,
          entry: entry,
          candidates: [
            for (final t in trainers)
              SchedulePerson(membershipId: t.membershipId, name: t.fullName)
          ],
        );
        if (substituteId == null || !mounted) return;
        await _run(
          () => api.swapInstructor(
            classInstanceId: entry.classInstanceId,
            substituteMembershipId: substituteId,
          ),
          'Substitute assigned',
        );

      case ScheduleAction.recurring:
        final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => RecurringChangeScreen(entry: entry),
        ));
        if (changed == true && mounted) Navigator.of(context).pop(true);

      case ScheduleAction.restore:
        await _run(() => api.restoreClass(entry.classInstanceId), 'Class restored');

      case ScheduleAction.undoSwap:
        await _run(() => api.undoSwap(entry.classInstanceId), 'Substitute removed');

      case ScheduleAction.undoReschedule:
        await _run(
            () => api.undoReschedule(entry.classInstanceId), 'Reschedule undone');

      case ScheduleAction.viewBatch:
        showAppToast(context, 'Opens Batches → Edit "${entry.batchName}"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = entry.courseCategory.meta(palette);
    final cancelled = entry.status == ScheduleEntryStatus.cancelled;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Class details',
                style: TextStyle(
                    fontSize: 17, fontWeight: AppType.bold, color: palette.text)),
            Text(entry.batchName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.page, AppSpacing.page, AppSpacing.x5l),
        children: [
          _summaryCard(palette, meta, cancelled),
          const SizedBox(height: AppSpacing.xxl),
          ..._changeNotices(palette),
          Text('OVERVIEW', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          _overview(palette, meta),
          const SizedBox(height: AppSpacing.xxl),
          Text('MAKE CHANGES', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          _actions(palette),
        ],
      ),
    );
  }

  Widget _summaryCard(AppPalette palette, CategoryMeta meta, bool cancelled) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: meta.soft,
              borderRadius: AppRadii.all(13),
            ),
            child: CourseIcon.forCourse(
              iconKey: entry.courseIconKey,
              category: entry.courseCategory,
              color: meta.color,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.batchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: AppType.bold,
                    color: cancelled ? palette.textMuted : palette.text,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(entry.courseName ?? 'Unlinked course',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppType.base,
                        fontWeight: AppType.medium,
                        color: meta.color)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
            decoration: BoxDecoration(
              color: entry.status.softColor(palette),
              borderRadius: AppRadii.all(AppRadii.smd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(scheduleStatusIcon(entry.status),
                    size: 11, color: entry.status.color(palette)),
                const SizedBox(width: 5),
                Text(entry.status.label,
                    style: TextStyle(
                      fontSize: AppType.tiny,
                      fontWeight: AppType.bold,
                      color: entry.status.color(palette),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The banner explaining what was done to this class. Only one can apply at a time, since a
  /// class carries one active override.
  List<Widget> _changeNotices(AppPalette palette) {
    Widget notice(Color color, Color soft, List<InlineSpan> spans) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline, size: 15, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: AppType.smd, color: palette.text, height: 1.5),
                      children: spans,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    final suffix = entry.reason == null ? '' : ' · ${entry.reason}';

    return switch (entry.status) {
      ScheduleEntryStatus.movedIn when entry.movedFrom != null => [
          notice(palette.gold, palette.goldSoft, [
            const TextSpan(text: 'Rescheduled from '),
            TextSpan(
                text: formatFeeDate(entry.movedFrom!),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: suffix),
          ])
        ],
      ScheduleEntryStatus.movedOut when entry.movedTo != null => [
          notice(palette.textFaint, palette.surfaceHigh, [
            const TextSpan(text: 'This session moved to '),
            TextSpan(
                text: formatFeeDate(entry.movedTo!),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: suffix),
          ])
        ],
      ScheduleEntryStatus.cancelled => [
          notice(palette.notPaid, palette.notPaidSoft,
              [TextSpan(text: 'Cancelled$suffix')])
        ],
      ScheduleEntryStatus.swapped => [
          notice(palette.violet, palette.violetSoft, [
            const TextSpan(text: 'Usually taught by '),
            TextSpan(
                text: entry.regularInstructorSummary,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: suffix),
          ])
        ],
      _ => const <Widget>[],
    };
  }

  Widget _overview(AppPalette palette, CategoryMeta meta) {
    final swapped = entry.status == ScheduleEntryStatus.swapped;

    final rows = <(IconData, String, String, Color?)>[
      (Icons.calendar_today_outlined, 'Date', formatFeeDate(entry.date), null),
      (Icons.schedule, 'Time', entry.timeRange, null),
      (
        Icons.menu_book_outlined,
        'Course',
        entry.courseName ?? '—',
        meta.color
      ),
      (
        Icons.groups_outlined,
        'Batch',
        '${entry.batchName}${entry.isTemporary ? ' · Temporary' : ''}',
        null
      ),
      (
        swapped ? Icons.manage_accounts_outlined : Icons.person_outline,
        swapped ? 'Substitute instructor' : 'Instructor',
        entry.instructorSummary,
        swapped ? palette.violet : null
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
              decoration: BoxDecoration(
                border: i < rows.length - 1
                    ? Border(bottom: BorderSide(color: palette.borderSoft))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(rows[i].$1, size: 15, color: palette.textMuted),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 82,
                    child: Text(rows[i].$2,
                        style: TextStyle(
                            fontSize: AppType.base, color: palette.textMuted)),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$3,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.lg,
                        fontWeight: AppType.semi,
                        color: rows[i].$4 ?? palette.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(AppPalette palette) {
    final actions = entry.availableActions;

    return Opacity(
      opacity: _busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.borderSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < actions.length; i++)
              Pressable(
                onTap: _busy ? null : () => _handle(actions[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                  decoration: BoxDecoration(
                    border: i < actions.length - 1
                        ? Border(bottom: BorderSide(color: palette.borderSoft))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          actions[i].label,
                          style: TextStyle(
                            fontSize: AppType.lg,
                            fontWeight: AppType.medium,
                            color: actions[i].danger ? palette.notPaid : palette.text,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 16,
                          color: actions[i].danger
                              ? palette.notPaid
                              : palette.textFaint),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

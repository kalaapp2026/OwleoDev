import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart'
    show formatTimeOfDay;
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/scheduling/presentation/class_detail_screen.dart';

/// How long after a reminder the bell stays "sent". Matches the server's cooldown, which refuses a
/// second one inside it - showing the bell as still available would only lead to a refusal.
const reminderCooldown = Duration(minutes: 10);

DateTime _at(DateTime date, String time) {
  final parts = time.split(':');
  return DateTime(
    date.year,
    date.month,
    date.day,
    int.tryParse(parts.first) ?? 0,
    parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

DateTime classStart(ScheduleEntry e) => _at(e.date, e.startTime);
DateTime classEnd(ScheduleEntry e) => _at(e.date, e.endTime);

/// Each batch's next class: the soonest one that is still going ahead and has not finished.
///
/// One entry per batch, ordered by when they happen - so a course with four batches yields four
/// rows, the earliest first. A class that is cancelled or moved away is skipped (the batch's next
/// real class is shown instead), and one already in progress still counts: it is the batch's
/// current class and the thing a reminder is most useful for.
List<ScheduleEntry> nextClassPerBatch(List<ScheduleEntry> feed, DateTime now) {
  const going = {
    ScheduleEntryStatus.scheduled,
    ScheduleEntryStatus.swapped,
    ScheduleEntryStatus.movedIn,
  };
  final upcoming =
      feed
          .where((e) => going.contains(e.status) && classEnd(e).isAfter(now))
          .toList()
        ..sort((a, b) => classStart(a).compareTo(classStart(b)));

  final byBatch = <String, ScheduleEntry>{};
  for (final e in upcoming) {
    byBatch.putIfAbsent(e.batchId, () => e);
  }
  return byBatch.values.toList();
}

/// "Today", "Tomorrow", or "Thu, 30 Oct".
String classDayLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[day.weekday - 1]}, ${day.day} ${monthsShort[day.month - 1]}';
}

/// The Dashboard's "Next class" section for an admin or trainer: one row per batch, each with a
/// bell that reminds that batch's students and trainers.
class NextClassesCard extends ConsumerStatefulWidget {
  const NextClassesCard({super.key});

  @override
  ConsumerState<NextClassesCard> createState() => _NextClassesCardState();
}

class _NextClassesCardState extends ConsumerState<NextClassesCard> {
  /// How many rows show before "Show all" - a course with a dozen batches should not push the
  /// rest of the Dashboard off the screen.
  static const _collapsedCount = 4;

  bool _showAll = false;
  final _sending = <String>{};

  /// Redraws every half minute. Everything on a row is relative to the clock - "Starts in 25 min",
  /// "Happening now", and whether the bell is back after its cooldown - and without this it only
  /// changed when something else happened to rebuild the card.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  ScheduleFeedKey get _key {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Five weeks: far enough that a batch which meets once a month still shows its next class.
    return (
      from: today,
      to: today.add(const Duration(days: 35)),
      courseId: null,
    );
  }

  bool _recentlyReminded(ScheduleEntry e, DateTime now) =>
      e.lastRemindedAt != null &&
      now.difference(e.lastRemindedAt!) < reminderCooldown;

  /// Tapping a row opens that class: its detail (reschedule, swap, cancel) for someone who manages
  /// the schedule, or the Attendance screen for a trainer who only marks attendance. Anyone else
  /// has nothing to open, so the row is not tappable for them.
  VoidCallback? _opener(ScheduleEntry e) {
    final user = ref.read(sessionControllerProvider).user;
    if (user == null) return null;
    final manages =
        user.isActiveAcademyAdmin ||
        user.hasFeature(FeatureKeys.reschedule) ||
        user.hasFeature(FeatureKeys.batchScheduling);
    if (manages) {
      return () async {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => ClassDetailScreen(entry: e)),
        );
        // A reschedule or cancellation changes which class is next, so refetch.
        if (changed == true) ref.invalidate(dashboardFeedProvider);
      };
    }
    if (user.hasFeature(FeatureKeys.attendance)) {
      return () => context.push('/erp/attendance');
    }
    return null;
  }

  Future<void> _remind(ScheduleEntry e) async {
    final now = DateTime.now();
    final when =
        '${classDayLabel(e.date, now)} at ${formatTimeOfDay(e.startTime)}';
    final people = e.studentCount == 0
        ? "the batch's instructors"
        : '${e.studentCount} student${e.studentCount == 1 ? '' : 's'} and the instructors';

    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Remind about this class?',
      message:
          'This sends a push notification to $people of ${e.batchName}: '
          '"This is your next class" - $when.',
      confirmLabel: 'Send reminder',
      cancelLabel: 'Cancel',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _sending.add(e.classInstanceId));
    try {
      final result = await ref
          .read(schedulingApiProvider)
          .remindClass(e.classInstanceId);
      // Refetch so the row picks up its "Reminded" time from the server rather than guessing it.
      ref.invalidate(dashboardFeedProvider);
      if (mounted) showAppToast(context, 'Reminder sent to ${result.summary}');
    } catch (err) {
      if (mounted) {
        showAppToast(
          context,
          err.toString().replaceFirst('Exception: ', ''),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sending.remove(e.classInstanceId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final feedAsync = ref.watch(dashboardFeedProvider(_key));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.x3l),
        border: Border.all(color: palette.border),
      ),
      child: feedAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(
          e.toString().replaceFirst('Exception: ', ''),
          style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
        ),
        data: (feed) {
          final now = DateTime.now();
          final next = nextClassPerBatch(feed, now);
          final shown = _showAll ? next : next.take(_collapsedCount).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Next class',
                style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppType.bold,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                next.isEmpty
                    ? 'Nothing coming up'
                    : '${next.length} batch${next.length == 1 ? '' : 'es'} · tap the bell to remind them',
                style: TextStyle(
                  fontSize: AppType.xs,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: palette.borderSoft),
              if (next.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    'No upcoming classes are scheduled for your batches.',
                    style: TextStyle(
                      fontSize: AppType.base,
                      color: palette.textFaint,
                    ),
                  ),
                )
              else
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.borderSoft),
                  _NextClassRow(
                    entry: shown[i],
                    now: now,
                    sending: _sending.contains(shown[i].classInstanceId),
                    reminded: _recentlyReminded(shown[i], now),
                    onOpen: _opener(shown[i]),
                    onRemind: () => _remind(shown[i]),
                  ),
                ],
              if (next.length > _collapsedCount) ...[
                Divider(height: 1, color: palette.borderSoft),
                Pressable(
                  onTap: () => setState(() => _showAll = !_showAll),
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Text(
                      _showAll
                          ? 'Show fewer'
                          : 'Show all ${next.length} batches',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppType.smd,
                        fontWeight: AppType.bold,
                        color: palette.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NextClassRow extends StatelessWidget {
  const _NextClassRow({
    required this.entry,
    required this.now,
    required this.sending,
    required this.reminded,
    required this.onRemind,
    this.onOpen,
  });

  final VoidCallback? onOpen;
  final ScheduleEntry entry;
  final DateTime now;
  final bool sending;
  final bool reminded;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = entry.courseCategory.meta(palette);

    final start = classStart(entry);
    final inProgress = !start.isAfter(now);
    final minutesAway = start.difference(now).inMinutes;
    final soon = !inProgress && minutesAway <= 120;

    // The line that matters most: when. "Happening now" and "Starts in 25 min" are more useful
    // than a clock time once the class is close.
    final (whenText, whenColor) = inProgress
        ? ('Happening now', palette.paidManual)
        : soon
        ? (
            'Starts in ${minutesAway < 60 ? '$minutesAway min' : '${minutesAway ~/ 60} h ${minutesAway % 60} min'}',
            palette.gold,
          )
        : (
            '${classDayLabel(entry.date, now)} · ${entry.timeRange}',
            palette.text,
          );

    final remindedAt = entry.lastRemindedAt;
    final details = [
      entry.instructorSummary,
      '${entry.studentCount} student${entry.studentCount == 1 ? '' : 's'}',
      if (remindedAt != null)
        'Reminded ${formatTimeOfDay('${remindedAt.hour}:${remindedAt.minute}')}',
    ].join(' · ');

    return Pressable(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
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
                iconKey: entry.courseIconKey,
                category: entry.courseCategory,
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
                  Text(
                    entry.batchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.xl,
                      fontWeight: AppType.semi,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    entry.courseName ?? 'Course',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.smd,
                      fontWeight: AppType.semi,
                      color: meta.color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    whenText,
                    style: TextStyle(
                      fontSize: AppType.base,
                      fontWeight: AppType.bold,
                      color: whenColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.xs,
                      color: palette.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _BellButton(sending: sending, reminded: reminded, onTap: onRemind),
          ],
        ),
      ),
    );
  }
}

/// The reminder bell at the row's right edge.
class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.sending,
    required this.reminded,
    required this.onTap,
  });

  final bool sending;
  final bool reminded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = reminded && !sending;
    final color = done ? palette.paidManual : palette.primary;

    return Tooltip(
      message: done ? 'Reminder sent' : 'Remind students and trainers',
      child: Pressable(
        // While one is in flight, or just sent, a second tap would only be refused.
        onTap: sending || done ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? palette.paidManualSoft : palette.primarySoft,
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: sending
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(
                  done
                      ? Icons.notifications_active
                      : Icons.notifications_active_outlined,
                  size: 18,
                  color: color,
                ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';

/// The 1st of the month after [today] - when a promotion's new fee starts unless another date is picked.
DateTime firstOfNextMonth(DateTime today) => DateTime(today.year, today.month + 1, 1);

/// "Move to another course" on a student's edit form: a student promoted from Basic to Advanced is billed
/// Advanced from the date picked (the 1st of next month unless changed), while this month's Basic slip,
/// already issued, stays as it is.
///
/// Scheduling changes nothing today; the server applies the move on its day. Until then it is listed here
/// and can be cancelled.
class CourseChangeSection extends ConsumerWidget {
  const CourseChangeSection({
    super.key,
    required this.membershipId,
    required this.studentName,
    required this.courses,
    required this.batches,
    required this.enrolledCourseIds,
    required this.accent,
  });

  final String membershipId;
  final String studentName;

  /// Every course the editor may choose between.
  final List<Course> courses;
  final List<Batch> batches;

  /// The courses the student is enrolled in today - what they can be moved out of.
  final Set<String> enrolledCourseIds;
  final Color accent;

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final from = courses.where((c) => enrolledCourseIds.contains(c.id)).toList();
    if (from.isEmpty) {
      showAppToast(context, 'This student is not enrolled in a course yet.', error: true);
      return;
    }
    final out = from.length == 1
        ? from.first
        : await showAppOptionSheet<Course>(
            context: context, title: 'Move out of', options: from, labelOf: (c) => c.name);
    if (out == null || !context.mounted) return;

    final targets = courses.where((c) => c.id != out.id && c.isActive).toList();
    if (targets.isEmpty) {
      showAppToast(context, 'There is no other active course to move to.', error: true);
      return;
    }
    final into = await showAppOptionSheet<Course>(
        context: context, title: 'Move ${out.name} to', options: targets, labelOf: (c) => c.name);
    if (into == null || !context.mounted) return;

    final today = DateUtils.dateOnly(DateTime.now());
    final defaultDate = firstOfNextMonth(today);
    DateTime date = defaultDate;
    final dateChoice = await showAppOptionSheet<bool>(
      context: context,
      title: 'Starts on',
      options: const [true, false],
      labelOf: (useDefault) =>
          useDefault ? '${formatFeeDate(defaultDate)} - start of next month' : 'Pick a different date',
    );
    if (dateChoice == null || !context.mounted) return;
    if (!dateChoice) {
      final picked = await showAppCalendar(
        context: context,
        month: defaultDate,
        selectedDay: defaultDate.day,
        earliestDay: today.add(const Duration(days: 1)),
      );
      if (picked == null || !context.mounted) return;
      date = picked;
    }

    final intoBatches = batches.where((b) => b.isActive && b.coversCourse(into.id)).toList();
    var chosenBatches = <Batch>[];
    if (intoBatches.isNotEmpty) {
      final place = await showAppOptionSheet<bool>(
        context: context,
        title: 'Place in a ${into.name} batch?',
        options: const [true, false],
        labelOf: (yes) => yes ? 'Choose batch(es)' : "No batch - I'll place them later",
      );
      if (place == null || !context.mounted) return;
      if (place) {
        chosenBatches = await showAppMultiSelectSheet<Batch>(
              context: context,
              title: '${into.name} batches',
              options: intoBatches,
              labelOf: (b) => b.name,
            ) ??
            [];
        if (!context.mounted) return;
      }
    }

    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Move $studentName?',
      message: 'From ${formatFeeDate(date)}, $studentName moves from ${out.name} to ${into.name}: '
          '${out.name} fees stop and ${into.name} fees start from that month. The fee slip already issued '
          "for this month is not changed.${chosenBatches.isEmpty ? '' : '\n\nThey will be placed in ${chosenBatches.map((b) => b.name).join(', ')}.'}",
      confirmLabel: 'Schedule',
      cancelLabel: 'Cancel',
      destructive: false,
    );
    if (!ok || !context.mounted) return;

    try {
      await ref.read(enrolmentApiProvider).scheduleCourseChange(
            membershipId,
            fromCourseId: out.id,
            toCourseId: into.id,
            effectiveOn: date,
            toBatchIds: chosenBatches.map((b) => b.id).toList(),
          );
      ref.invalidate(studentCourseChangesProvider(membershipId));
      if (context.mounted) showAppToast(context, 'Move scheduled for ${formatFeeDate(date)}');
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, CourseChange change) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Cancel this move?',
      message: '$studentName stays on ${change.fromCourseName}. Nothing else changes.',
      confirmLabel: 'Cancel move',
      cancelLabel: 'Keep it',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(enrolmentApiProvider).cancelCourseChange(change.id);
      ref.invalidate(studentCourseChangesProvider(membershipId));
      if (context.mounted) showAppToast(context, 'Move cancelled');
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final pending = ref.watch(studentCourseChangesProvider(membershipId)).valueOrNull ?? const <CourseChange>[];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.x4l),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 16, color: accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Move to another course',
                    style: TextStyle(
                        fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Promote $studentName - say Basic to Advanced. The new course is billed from the date you pick '
            '(next month by default); this month\'s fee slip is left alone.',
            style: TextStyle(fontSize: AppType.sm, color: palette.textFaint, height: 1.45),
          ),
          for (final change in pending) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.goldSoft,
                borderRadius: AppRadii.all(AppRadii.lg),
                border: Border.all(color: palette.gold.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 15, color: palette.gold),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${change.fromCourseName} → ${change.toCourseName}',
                            style: TextStyle(
                                fontSize: AppType.lg,
                                fontWeight: AppType.bold,
                                color: palette.text)),
                        Text(
                          'From ${formatFeeDate(change.effectiveOn)}'
                          '${change.toBatchNames.isEmpty ? '' : ' · ${change.toBatchNames.join(', ')}'}',
                          style: TextStyle(fontSize: AppType.sm, color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => _cancel(context, ref, change),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(Icons.close_rounded, size: 16, color: palette.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Schedule a course move',
            icon: Icons.swap_horiz,
            onPressed: () => _schedule(context, ref),
          ),
        ],
      ),
    );
  }
}

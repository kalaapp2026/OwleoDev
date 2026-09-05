import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';

/// The icon that goes with each status, so the badge reads at a glance without relying on colour
/// alone (which excludes anyone who can't distinguish the accents).
IconData scheduleStatusIcon(ScheduleEntryStatus status) => switch (status) {
      ScheduleEntryStatus.scheduled => Icons.schedule,
      ScheduleEntryStatus.swapped => Icons.manage_accounts_outlined,
      ScheduleEntryStatus.movedIn => Icons.refresh,
      ScheduleEntryStatus.movedOut => Icons.refresh,
      ScheduleEntryStatus.cancelled => Icons.block,
      ScheduleEntryStatus.held => Icons.check_circle_outline,
    };

/// One class in the schedule feed.
///
/// A vacated slot (movedOut) is drawn as a dashed outline with no fill - it is a note saying
/// where a class used to be, and giving it the same solid card as a real class would have people
/// turning up to it.
class ScheduleRow extends StatelessWidget {
  const ScheduleRow({
    super.key,
    required this.entry,
    required this.kebabOpen,
    required this.onToggleKebab,
    required this.onAction,
    required this.onOpenDetail,
  });

  final ScheduleEntry entry;
  final bool kebabOpen;
  final VoidCallback onToggleKebab;
  final ValueChanged<ScheduleAction> onAction;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = entry.courseCategory.meta(palette);
    final ghost = entry.status.isGhost;
    final cancelled = entry.status == ScheduleEntryStatus.cancelled;

    return Pressable(
      onTap: onOpenDetail,
      child: Opacity(
        opacity: ghost || cancelled ? 0.72 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: ghost ? Colors.transparent : palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: ghost ? palette.border : palette.borderSoft),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(top: 2),
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
                  Expanded(child: _details(palette, meta.color, cancelled)),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _statusBadge(palette),
                      const SizedBox(height: AppSpacing.xs),
                      _kebab(palette),
                    ],
                  ),
                ],
              ),
              // A temporary batch's class is worth flagging on the feed - it doesn't follow the
              // course's usual fee or attendance expectations.
              if (entry.isTemporary && !ghost)
                Positioned(
                  top: -AppSpacing.lg,
                  right: 40,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
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
      ),
    );
  }

  Widget _details(AppPalette palette, Color accent, bool cancelled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          children: [
            Text(
              entry.batchName,
              style: TextStyle(
                fontSize: AppType.xxl,
                fontWeight: AppType.semi,
                color: cancelled ? palette.textMuted : palette.text,
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(
              entry.timeRange,
              style: TextStyle(
                fontSize: AppType.base,
                fontWeight: AppType.medium,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          entry.courseName ?? 'Unlinked course',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: AppType.smd, fontWeight: AppType.medium, color: accent),
        ),
        const SizedBox(height: 2),
        _instructorLine(palette),
        if (entry.status == ScheduleEntryStatus.movedIn && entry.movedFrom != null)
          _note(palette, palette.gold, Icons.refresh,
              'Rescheduled from ${formatFeeDate(entry.movedFrom!)}'
              '${entry.reason == null ? '' : ' · ${entry.reason}'}'),
        if (entry.status == ScheduleEntryStatus.movedOut && entry.movedTo != null)
          _note(palette, palette.textFaint, Icons.arrow_forward,
              'Moved to ${formatFeeDate(entry.movedTo!)}'),
        if (entry.status == ScheduleEntryStatus.cancelled)
          _note(palette, palette.notPaid, null,
              'Cancelled${entry.reason == null ? '' : ' · ${entry.reason}'}'),
      ],
    );
  }

  Widget _instructorLine(AppPalette palette) {
    if (entry.status != ScheduleEntryStatus.swapped) {
      return Text(
        entry.instructorSummary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
      );
    }
    // Naming both the stand-in and the usual instructor: the reader's question on seeing an
    // unfamiliar name is always "wasn't this someone else's class?"
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
        children: [
          const TextSpan(text: 'Substitute: '),
          TextSpan(
            text: entry.instructorSummary,
            style: TextStyle(fontWeight: AppType.bold, color: palette.violet),
          ),
          TextSpan(text: ' (usually ${entry.regularInstructorSummary})'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _note(AppPalette palette, Color color, IconData? icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 11, color: color),
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: AppType.xs, fontWeight: AppType.medium, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(AppPalette palette) {
    final color = entry.status.color(palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: entry.status.softColor(palette),
        borderRadius: AppRadii.all(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(scheduleStatusIcon(entry.status), size: 10, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            entry.status.label,
            style: TextStyle(
                fontSize: AppType.tiny, fontWeight: AppType.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _kebab(AppPalette palette) {
    final actions = entry.availableActions;
    return AttachedSelect<ScheduleAction>(
      label: '',
      options: actions,
      labelOf: (a) => a.label,
      isOpen: kebabOpen,
      onOpenChanged: (_) => onToggleKebab(),
      panelWidth: 200,
      panelSpan: PanelSpan.right,
      onSelected: onAction,
      optionBuilder: (context, option, _) => Text(
        option.label,
        style: TextStyle(
          fontSize: AppType.lg,
          fontWeight: AppType.regular,
          color: option.danger ? palette.notPaid : palette.text,
        ),
      ),
      triggerBuilder: (context, isOpen, toggle) =>
          AppIconButton(icon: Icons.more_vert, onTap: toggle, size: 28, iconSize: 14),
    );
  }
}

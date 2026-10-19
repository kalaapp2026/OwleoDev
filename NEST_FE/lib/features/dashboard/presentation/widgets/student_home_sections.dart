import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/month_grid_calendar.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart' show formatTimeOfDay;
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "19 Oct 2026" - the prototype's day label.
String _dayLabel(DateTime d) => '${d.day} ${monthsShort[d.month - 1]} ${d.year}';

/// The day the home screen's class list is showing; the Today tile and the Calendar button both set it.
final studentHomeDayProvider = StateProvider<DateTime>((ref) => _dateOnly(DateTime.now()));

/// Opens the class calendar and, if a day was picked, shows that day's classes on the home screen.
Future<void> openStudentClassCalendar(BuildContext context, WidgetRef ref) async {
  final picked = await showStudentClassCalendar(context, selected: ref.read(studentHomeDayProvider));
  if (picked != null) ref.read(studentHomeDayProvider.notifier).state = picked;
}

/// A section title with an optional action on the right ("See all >", "Calendar").
class StudentSectionHeader extends StatelessWidget {
  const StudentSectionHeader({super.key, required this.title, this.actionLabel, this.actionIcon, this.onAction});

  final String title;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text)),
        if (actionLabel != null)
          Pressable(
            onTap: onAction,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (actionIcon != null) ...[
                Icon(actionIcon, size: 12.5, color: palette.primary),
                const SizedBox(width: 3),
              ],
              Text(actionLabel!, style: TextStyle(fontSize: 11, fontWeight: AppType.bold, color: palette.primary)),
              if (actionIcon == null) Icon(Icons.chevron_right, size: 13, color: palette.primary),
            ]),
          ),
      ]),
    );
  }
}

/// "Today's classes" - the classes on one day, with a Calendar button that opens a month view to
/// jump to another day ("Classes on 21 Oct 2026").
class StudentClassesSection extends ConsumerStatefulWidget {
  const StudentClassesSection({super.key});

  @override
  ConsumerState<StudentClassesSection> createState() => _StudentClassesSectionState();
}

class _StudentClassesSectionState extends ConsumerState<StudentClassesSection> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final view = ref.watch(studentHomeDayProvider);
    final isToday = view == _dateOnly(DateTime.now());
    final feed = ref.watch(scheduleFeedProvider((from: view, to: view, courseId: null)));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StudentSectionHeader(
        title: isToday ? "Today's classes" : 'Classes on ${_dayLabel(view)}',
        actionLabel: 'Calendar',
        actionIcon: Icons.calendar_today_outlined,
        onAction: () => openStudentClassCalendar(context, ref),
      ),
      AsyncValueView<List<ScheduleEntry>>(
        value: feed,
        onRetry: () => ref.invalidate(scheduleFeedProvider((from: view, to: view, courseId: null))),
        data: (context, entries) {
          final day = entries.where((e) => !e.status.isGhost && _dateOnly(e.date) == view).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
          if (day.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: AppRadii.all(AppRadii.xl),
                border: Border.all(color: palette.border),
              ),
              child: Text('No classes on this day',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: palette.textFaint)),
            );
          }
          return Column(children: [
            for (final e in day) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ClassCard(entry: e)),
          ]);
        },
      ),
    ]);
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.entry});
  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = entry.courseCategory.meta(palette);
    final cancelled = entry.status == ScheduleEntryStatus.cancelled;
    final trainer = entry.instructors.isEmpty ? null : entry.instructors.first.name.trim().split(RegExp(r'\s+')).first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: meta.soft, borderRadius: AppRadii.all(11)),
          child: Center(
            child: CourseIcon.forCourse(iconKey: entry.courseIconKey, category: entry.courseCategory, color: meta.color),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.courseName ?? 'Course',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: AppType.bold,
                  color: cancelled ? palette.textFaint : palette.text,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                )),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.schedule, size: 11, color: palette.textFaint),
              const SizedBox(width: 3),
              Flexible(
                child: Text('${formatTimeOfDay(entry.startTime)}–${formatTimeOfDay(entry.endTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
              ),
              const SizedBox(width: 8),
              Icon(Icons.layers_outlined, size: 11, color: palette.textFaint),
              const SizedBox(width: 3),
              Flexible(
                child: Text(entry.batchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        if (cancelled)
          Text('Cancelled', style: TextStyle(fontSize: 10, fontWeight: AppType.bold, color: palette.notPaid))
        else if (entry.status == ScheduleEntryStatus.movedIn)
          Text('Rescheduled', style: TextStyle(fontSize: 10, fontWeight: AppType.bold, color: palette.gold))
        else if (trainer != null)
          Text(trainer, style: TextStyle(fontSize: 10, fontWeight: AppType.bold, color: meta.color)),
      ]),
    );
  }
}

/// The month calendar behind the Calendar button: a dot per category on every day that has
/// classes, tap a day to list them and jump to it. Returns the day to show, or null if closed.
Future<DateTime?> showStudentClassCalendar(BuildContext context, {required DateTime selected}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: const Color(0x73241B10),
    builder: (_) => _ClassCalendarDialog(selected: selected),
  );
}

class _ClassCalendarDialog extends ConsumerStatefulWidget {
  const _ClassCalendarDialog({required this.selected});
  final DateTime selected;

  @override
  ConsumerState<_ClassCalendarDialog> createState() => _ClassCalendarDialogState();
}

class _ClassCalendarDialogState extends ConsumerState<_ClassCalendarDialog> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  final Map<DateTime, List<ScheduleEntry>> _byDay = {};
  DateTime? _expanded;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final month = _month;
    try {
      final entries = await ref.read(schedulingApiProvider).feed(
            from: DateTime(month.year, month.month, 1),
            to: DateTime(month.year, month.month + 1, 0),
            courseId: null,
          );
      if (!mounted || request != _request) return;
      setState(() {
        _byDay.removeWhere((d, _) => d.year == month.year && d.month == month.month);
        for (final e in entries.where((e) => e.status.meets)) {
          _byDay.putIfAbsent(_dateOnly(e.date), () => []).add(e);
        }
      });
    } catch (_) {
      // Dots are decoration - a failed load leaves a plain, still-usable calendar.
    }
  }

  List<ScheduleEntry> _classesOn(DateTime d) => _byDay[d] ?? const [];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final today = _dateOnly(DateTime.now());

    // One legend entry per category that has a class this month.
    final legend = <CourseCategory, Color>{};
    for (final e in _byDay.entries) {
      if (e.key.year != _month.year || e.key.month != _month.month) continue;
      for (final c in e.value) {
        legend.putIfAbsent(c.courseCategory, () => c.courseCategory.meta(palette).color);
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.all(AppRadii.x4l),
          border: Border.all(color: palette.border),
          boxShadow: AppShadows.dialog,
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            MonthGridCalendar(
              initialMonth: _month,
              onMonthChanged: (m) {
                setState(() {
                  _month = m;
                  _expanded = null;
                });
                _load();
              },
              expandedDay: _expanded,
              expandedBuilder: (day) => _DayPanel(
                day: day,
                classes: _classesOn(day),
                onGo: () => Navigator.of(context).pop(day),
              ),
              onDayTap: (day) {
                if (_classesOn(day).isEmpty) return;
                setState(() => _expanded = _expanded == day ? null : day);
              },
              cellFor: (day) {
                final classes = _classesOn(day);
                final isSelected = day == widget.selected;
                final isToday = day == today;
                final isExpanded = day == _expanded;
                final cats = <Color>[];
                for (final c in classes) {
                  final color = c.courseCategory.meta(palette).color;
                  if (!cats.contains(color)) cats.add(color);
                }
                return MonthCell(
                  background: isSelected ? palette.gold : isExpanded ? palette.goldSoft : null,
                  borderColor: isExpanded || (isToday && !isSelected) ? palette.gold : null,
                  textColor: isSelected ? Colors.white : isToday ? palette.gold : palette.text,
                  bold: isSelected || isToday,
                  dots: isSelected ? [for (final _ in cats) Colors.white] : cats,
                  tappable: classes.isNotEmpty,
                );
              },
            ),
            if (legend.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 4, children: [
                for (final e in legend.entries)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: e.value, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(e.key.label,
                        style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textMuted)),
                  ]),
              ]),
            ],
            const SizedBox(height: 16),
            Pressable(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                child: Text('Close', style: TextStyle(fontSize: 14, fontWeight: AppType.bold, color: palette.notPaid)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DayPanel extends StatelessWidget {
  const _DayPanel({required this.day, required this.classes, required this.onGo});

  final DateTime day;
  final List<ScheduleEntry> classes;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sorted = [...classes]..sort((a, b) => a.startTime.compareTo(b.startTime));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
          child: Text(_dayLabel(day).toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, letterSpacing: 0.4, color: palette.textMuted)),
        ),
        for (final c in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c.courseCategory.meta(palette).color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.courseName ?? 'Course'} · ${c.batchName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.text)),
                  const SizedBox(height: 1),
                  Text('${formatTimeOfDay(c.startTime)}–${formatTimeOfDay(c.endTime)}',
                      style: TextStyle(fontSize: 11, color: palette.textFaint)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 6),
        Pressable(
          onTap: onGo,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: palette.gold, borderRadius: AppRadii.all(AppRadii.smd)),
            child: const Text('Go to this day',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

final _studentEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, academyId) {
  return ref.watch(eventsApiProvider).forAcademy(academyId);
});

/// The next events at the academy as small date cards in a row. The same rule as the Events
/// screen's Upcoming tab - an event that runs over several days stays here until its last day.
class StudentUpcomingEvents extends ConsumerWidget {
  const StudentUpcomingEvents({super.key, required this.academyId});

  final String academyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final today = _dateOnly(DateTime.now());
    final accents = [palette.primary, palette.gold, palette.violet, palette.coral, palette.gateway];
    final async = ref.watch(_studentEventsProvider(academyId));

    DateTime day(String iso) => _dateOnly(DateTime.tryParse(iso) ?? today);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StudentSectionHeader(title: 'Upcoming events', actionLabel: 'See all', onAction: () => context.push('/erp/events')),
      AsyncValueView<List<Event>>(
        value: async,
        onRetry: () => ref.invalidate(_studentEventsProvider(academyId)),
        data: (context, all) {
          final upcoming = all
              .where((e) => !e.isDraft && !e.isCancelled && !day(e.endDate ?? e.eventDate).isBefore(today))
              .toList()
            ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
          if (upcoming.isEmpty) {
            return Text('No upcoming events.', style: TextStyle(fontSize: 12, color: palette.textFaint));
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < upcoming.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _EventTile(event: upcoming[i], accent: accents[i % accents.length]),
                ],
              ]),
            ),
          );
        },
      ),
    ]);
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.accent});
  final Event event;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final date = DateTime.tryParse(event.eventDate);
    return Pressable(
      onTap: () => context.push('/erp/events'),
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Container(
        constraints: const BoxConstraints(minWidth: 130, maxWidth: 190),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (date != null)
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('${date.day}', style: TextStyle(fontSize: 18, fontWeight: AppType.heavy, color: accent)),
              const SizedBox(width: 4),
              Text(monthsShort[date.month - 1],
                  style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, color: palette.textMuted)),
            ]),
          const SizedBox(height: 6),
          Text(event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, height: 1.3, fontWeight: AppType.bold, color: palette.text)),
          if ((event.location ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(event.location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
          ],
        ]),
      ),
    );
  }
}

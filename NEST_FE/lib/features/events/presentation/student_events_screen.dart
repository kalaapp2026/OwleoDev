import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/month_grid_calendar.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/shell/presentation/header_actions.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;
import 'package:url_launcher/url_launcher.dart';

final _myEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, academyId) {
  return ref.watch(eventsApiProvider).forAcademy(academyId);
});

enum _Tab { upcoming, past }

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

DateTime _day(String iso) {
  final d = DateTime.tryParse(iso) ?? DateTime.now();
  return DateTime(d.year, d.month, d.day);
}

/// A student's Events: only what is aimed at them (the server filters by audience), split into
/// Upcoming and Past, with an "I'm interested" toggle that stops accepting new interest after the
/// event's deadline, and a calendar to find the events on a particular day.
class StudentEventsScreen extends ConsumerStatefulWidget {
  const StudentEventsScreen({super.key});

  @override
  ConsumerState<StudentEventsScreen> createState() => _State();
}

class _State extends ConsumerState<StudentEventsScreen> {
  _Tab _tab = _Tab.upcoming;
  DateTime? _filterDay;
  // Optimistic override of interestedByMe per event, until the next refetch confirms it.
  final Map<String, bool> _interest = {};

  bool _on(Event e) => _interest[e.id] ?? e.interestedByMe;

  /// How many people are interested, counting the toggle the student just made before the server confirms.
  int _count(Event e) {
    final override = _interest[e.id];
    if (override == null || override == e.interestedByMe) return e.interestedCount;
    return (e.interestedCount + (override ? 1 : -1)).clamp(0, 1 << 30);
  }

  bool _closed(Event e) {
    final d = e.interestDeadline == null ? null : DateTime.tryParse(e.interestDeadline!);
    if (d == null) return false;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day).isAfter(DateTime(d.year, d.month, d.day));
  }

  Future<void> _toggle(Event e, String academyId) async {
    final turnOn = !_on(e);
    if (turnOn && _closed(e)) return;
    setState(() => _interest[e.id] = turnOn);
    try {
      final api = ref.read(eventsApiProvider);
      turnOn ? await api.markInterested(e.id) : await api.unmarkInterested(e.id);
      if (mounted) showAppToast(context, turnOn ? 'Marked as interested' : 'Removed from interested');
      ref.invalidate(_myEventsProvider(academyId));
    } catch (_) {
      if (mounted) {
        setState(() => _interest[e.id] = !turnOn);
        showAppToast(context, "Couldn't update — try again", error: true);
      }
    }
  }

  Future<void> _openCalendar(List<Event> events) async {
    final picked = await showDialog<DateTime?>(
      context: context,
      barrierColor: const Color(0x73241B10),
      builder: (_) => _EventCalendarDialog(events: events, selected: _filterDay),
    );
    // Close returns null without touching the filter; Clear filter returns a sentinel.
    if (!mounted) return;
    if (picked == _clearFilter) {
      setState(() => _filterDay = null);
    } else if (picked != null) {
      setState(() => _filterDay = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final membership = ref.watch(sessionControllerProvider).user?.activeMembership;
    final academyId = membership?.academyId;
    final user = ref.watch(sessionControllerProvider).user;
    if (academyId == null) return const SizedBox.shrink();
    final async = ref.watch(_myEventsProvider(academyId));
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(children: [
          AppTopBar(title: 'Events', subtitle: user?.fullName, actions: kStudentTopBarActions),
          Expanded(
            child: AsyncValueView<List<Event>>(
              value: async,
              onRetry: () => ref.invalidate(_myEventsProvider(academyId)),
              data: (context, all) {
                final events = all.where((e) => !e.isDraft).toList();
                DateTime end(Event e) => _day(e.endDate ?? e.eventDate);
                final upcoming = events.where((e) => !end(e).isBefore(todayDay)).toList()
                  ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
                final past = events.where((e) => end(e).isBefore(todayDay)).toList()
                  ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
                var shown = _tab == _Tab.upcoming ? upcoming : past;
                final filter = _filterDay;
                if (filter != null) {
                  shown = events.where((e) {
                    final start = _day(e.eventDate);
                    return !filter.isBefore(start) && !filter.isAfter(end(e));
                  }).toList()
                    ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
                }
                final heading = filter != null
                    ? 'Events on ${formatFeeDate(filter)}'
                    : _tab == _Tab.upcoming ? 'Upcoming events' : 'Past events';
                final emptyText = filter != null
                    ? 'No events on this date'
                    : _tab == _Tab.upcoming ? 'No upcoming events at this academy' : 'No past events yet';
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_myEventsProvider(academyId)),
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
                    AcademyPill(name: membership?.academyName ?? ''),
                    const SizedBox(height: 14),
                    GoldTabs<_Tab>(
                      options: _Tab.values,
                      labelOf: (t) => t == _Tab.upcoming ? 'Upcoming' : 'Past',
                      badgeOf: (t) => t == _Tab.upcoming ? upcoming.length : past.length,
                      selected: _tab,
                      onTap: (t) => setState(() {
                        _tab = t;
                        _filterDay = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Pressable(
                        onTap: () => _openCalendar(events),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: filter != null ? palette.goldSoft : palette.surfaceRaised,
                            borderRadius: AppRadii.all(AppRadii.md),
                            border: Border.all(color: filter != null ? palette.gold : palette.border),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.calendar_today_outlined, size: 13, color: filter != null ? palette.gold : palette.textMuted),
                            const SizedBox(width: 6),
                            Text(filter != null ? formatFeeDate(filter) : 'View calendar',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: AppType.bold,
                                    color: filter != null ? palette.gold : palette.textMuted)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(heading, style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text)),
                    const SizedBox(height: 10),
                    if (shown.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 10),
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          borderRadius: AppRadii.all(AppRadii.xl),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(emptyText,
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: palette.textFaint)),
                      ),
                    for (final e in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EventCard(
                          event: e,
                          interested: _on(e),
                          interestedCount: _count(e),
                          closed: _closed(e),
                          onOpen: () => _openDetail(e, academyId),
                          onToggle: () => _toggle(e, academyId),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _openDetail(Event e, String academyId) {
    final palette = context.palette;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => _EventSheet(
          event: e,
          interested: _on(e),
          interestedCount: _count(e),
          closed: _closed(e),
          onToggle: () async {
            await _toggle(e, academyId);
            setSheet(() {});
          },
        ),
      ),
    );
  }
}

/// A date no calendar can return, standing for "Clear filter".
final DateTime _clearFilter = DateTime.utc(1900);

/// "Sunday, 18 Oct 2026" - or "19 Sep 2026 – 20 Sep 2026" for an event that runs over several days.
String _dateLabel(Event e) {
  final s = DateTime.tryParse(e.eventDate);
  if (s == null) return e.eventDate;
  if (!e.isMultiDay) return '${_weekdays[s.weekday - 1]}, ${formatFeeDate(s)}';
  final en = DateTime.tryParse(e.endDate!);
  return '${formatFeeDate(s)} – ${en == null ? '' : formatFeeDate(en)}';
}

String? _timeLabel(Event e) {
  final s = DateTime.tryParse(e.eventDate);
  if (s == null || (s.hour == 0 && s.minute == 0)) return null;
  String fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
  final en = e.endDate == null ? null : DateTime.tryParse(e.endDate!);
  return en == null || (en.hour == 0 && en.minute == 0) ? fmt(s) : '${fmt(s)} – ${fmt(en)}';
}

String _audienceLabel(Event e) => switch (e.audienceType) {
      'ALL_STUDENTS' => 'All students',
      'BY_COURSE' => 'Your course',
      'BY_BATCH' => 'Your batch',
      'INDIVIDUALS' => 'Just for you',
      _ => 'Event',
    };

Color _audienceColor(AppPalette p, Event e) => switch (e.audienceType) {
      'ALL_STUDENTS' => p.gold,
      'INDIVIDUALS' => p.violet,
      _ => p.primary,
    };

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color, {this.soft});
  final String label;
  final Color color;
  final Color? soft;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: soft ?? color.withValues(alpha: 0.1), borderRadius: AppRadii.all(6)),
        child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: AppType.heavy, color: color)),
      );
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.interested,
    required this.interestedCount,
    required this.closed,
    required this.onOpen,
    required this.onToggle,
  });

  final Event event;
  final bool interested;
  final int interestedCount;
  final bool closed;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _audienceColor(palette, event);
    final cancelled = event.isCancelled;
    final time = _timeLabel(event);
    final public = event.visibility == 'PUBLIC';
    return Opacity(
      opacity: cancelled ? 0.65 : 1,
      child: Pressable(
        onTap: onOpen,
        borderRadius: AppRadii.all(AppRadii.xxl),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.borderSoft),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: AppRadii.all(AppRadii.lg),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(Icons.calendar_today_outlined, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: AppType.bold, fontSize: 14, color: palette.text)),
                  ),
                  if (cancelled) ...[
                    const SizedBox(width: 6),
                    _Chip('CANCELLED', palette.notPaid, soft: palette.notPaidSoft),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(time == null ? _dateLabel(event) : '${_dateLabel(event)} · $time',
                    style: TextStyle(fontSize: 11.5, fontWeight: AppType.semi, color: palette.textMuted)),
                if ((event.location ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.place_outlined, size: 11, color: palette.textFaint),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(event.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
                    ),
                    if ((event.venueMapsUrl ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Pressable(
                        onTap: () => launchUrl(Uri.parse(event.venueMapsUrl!), mode: LaunchMode.externalApplication),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.open_in_new, size: 10, color: palette.gateway),
                          const SizedBox(width: 3),
                          Text('Directions',
                              style: TextStyle(fontSize: 10.5, fontWeight: AppType.bold, color: palette.gateway)),
                        ]),
                      ),
                    ],
                  ]),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _Chip(_audienceLabel(event), color),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(public ? Icons.public : Icons.apartment_outlined, size: 11, color: palette.textFaint),
                    const SizedBox(width: 3),
                    Text(public ? 'Public' : 'In-house',
                        style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: palette.textMuted)),
                  ]),
                  if (interestedCount > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star_border, size: 11, color: palette.gold),
                      const SizedBox(width: 3),
                      Text('$interestedCount interested',
                          style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: palette.gold)),
                    ]),
                ]),
                if (!cancelled) ...[
                  const SizedBox(height: 8),
                  _InterestButton(interested: interested, closed: closed, onTap: onToggle),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _InterestButton extends StatelessWidget {
  const _InterestButton({required this.interested, required this.closed, required this.onTap, this.big = false});
  final bool interested;
  final bool closed;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disabled = closed && !interested;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Pressable(
        onTap: disabled ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: big ? 12 : 7),
          decoration: BoxDecoration(
            color: interested ? palette.primary : Colors.transparent,
            borderRadius: AppRadii.all(big ? AppRadii.lg : AppRadii.md),
            border: interested ? null : Border.all(color: palette.border),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(interested ? Icons.star : Icons.star_border,
                size: big ? 14 : 12, color: interested ? palette.onPrimary : palette.textMuted),
            const SizedBox(width: 6),
            Text(
                interested
                    ? (big ? "You're interested" : 'Interested')
                    : closed
                        ? 'RSVP closed'
                        : "I'm interested",
                style: TextStyle(
                    fontSize: big ? 13 : 11,
                    fontWeight: AppType.bold,
                    color: interested ? palette.onPrimary : (big ? palette.text : palette.textMuted))),
          ]),
        ),
      ),
    );
  }
}

class _EventSheet extends StatelessWidget {
  const _EventSheet({
    required this.event,
    required this.interested,
    required this.interestedCount,
    required this.closed,
    required this.onToggle,
  });
  final Event event;
  final bool interested;
  final int interestedCount;
  final bool closed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _audienceColor(palette, event);
    final time = _timeLabel(event);
    final public = event.visibility == 'PUBLIC';
    Widget row(IconData icon, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 13, color: palette.textFaint),
            const SizedBox(width: 8),
            SizedBox(width: 78, child: Text(k, style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textFaint))),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11.5, fontWeight: AppType.bold, color: palette.text)),
            ),
          ]),
        );
    final deadline = event.interestDeadline == null ? null : DateTime.tryParse(event.interestDeadline!);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SizedBox(width: 28),
            Expanded(
              child: Text(event.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text)),
            ),
            Pressable(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: AppRadii.all(9),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.close, size: 14, color: palette.textMuted),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _Chip(_audienceLabel(event), color),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.sm)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(public ? Icons.public : Icons.apartment_outlined, size: 11, color: palette.textMuted),
                const SizedBox(width: 4),
                Text(public ? 'Public' : 'In-house',
                    style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: palette.textMuted)),
              ]),
            ),
            if (event.isCancelled) _Chip('CANCELLED', palette.notPaid, soft: palette.notPaidSoft),
          ]),
          if ((event.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(event.description!, style: TextStyle(fontSize: 11.5, height: 1.5, color: palette.textMuted)),
          ],
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.border),
            ),
            child: Column(children: [
              row(Icons.calendar_today_outlined, 'Date', _dateLabel(event)),
              if (time != null) row(Icons.schedule, 'Time', time),
              if ((event.location ?? '').isNotEmpty) row(Icons.place_outlined, 'Venue', event.location!),
            ]),
          ),
          if ((event.venueMapsUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => launchUrl(Uri.parse(event.venueMapsUrl!), mode: LaunchMode.externalApplication),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_new, size: 13, color: palette.gateway),
                  const SizedBox(width: 6),
                  Text('Open in Google Maps',
                      style: TextStyle(fontSize: 12, fontWeight: AppType.bold, color: palette.gateway)),
                ]),
              ),
            ),
          ],
          if (deadline != null && !event.isCancelled) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                borderRadius: AppRadii.all(AppRadii.lg),
                border: Border.all(color: palette.borderSoft),
              ),
              child: Row(children: [
                Icon(Icons.schedule, size: 13, color: palette.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    closed
                        ? 'Interest can no longer be marked for this event'
                        : 'Interest can be marked until ${formatFeeDate(deadline)}',
                    style: TextStyle(fontSize: 11.5, color: palette.textMuted),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.star_border, size: 13, color: palette.textFaint),
            const SizedBox(width: 6),
            Text('$interestedCount student${interestedCount == 1 ? '' : 's'} interested',
                style: TextStyle(fontSize: 11.5, color: palette.textMuted)),
          ]),
          const SizedBox(height: 16),
          if (event.isCancelled)
            Center(child: Text('This event has been cancelled', style: TextStyle(fontSize: 11, color: palette.textFaint)))
          else
            _InterestButton(interested: interested, closed: closed, onTap: onToggle, big: true),
        ]),
      ),
    );
  }
}

/// The events calendar: a dot per audience on each day that has events, tap a day to filter the list
/// to it.
class _EventCalendarDialog extends StatefulWidget {
  const _EventCalendarDialog({required this.events, required this.selected});
  final List<Event> events;
  final DateTime? selected;

  @override
  State<_EventCalendarDialog> createState() => _EventCalendarDialogState();
}

class _EventCalendarDialogState extends State<_EventCalendarDialog> {
  DateTime? _picked;

  List<Event> _on(DateTime d) => widget.events.where((e) {
        final start = _day(e.eventDate);
        final end = _day(e.endDate ?? e.eventDate);
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final base = widget.selected ?? todayDay;

    final legend = [
      ('All students', palette.gold),
      ('Course / Batch', palette.primary),
      ('Individual invite', palette.violet),
    ];

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
              initialMonth: DateTime(base.year, base.month),
              firstYear: 2000,
              lastYear: 2040,
              yearTileColor: palette.surfaceRaised,
              cellFor: (day) {
                final events = _on(day).where((e) => !e.isDraft).toList();
                final isToday = day == todayDay;
                final isPicked = day == (_picked ?? widget.selected);
                final colors = <Color>[];
                for (final e in events) {
                  final c = _audienceColor(palette, e);
                  if (!colors.contains(c)) colors.add(c);
                }
                return MonthCell(
                  background: isPicked ? palette.goldSoft : null,
                  borderColor: isToday || isPicked ? palette.gold : null,
                  textColor: isToday ? palette.gold : palette.text,
                  bold: isToday,
                  dots: colors,
                );
              },
              onDayTap: (day) => Navigator.of(context).pop(day),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 4, children: [
              for (final l in legend)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: l.$2, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(l.$1, style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textMuted)),
                ]),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.selected != null) ...[
                Pressable(
                  onTap: () => Navigator.of(context).pop(_clearFilter),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Clear filter',
                        style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.textMuted)),
                  ),
                ),
                const SizedBox(width: 18),
              ],
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Close', style: TextStyle(fontSize: 14, fontWeight: AppType.bold, color: palette.notPaid)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

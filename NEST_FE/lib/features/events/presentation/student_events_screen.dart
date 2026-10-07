import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;
import 'package:url_launcher/url_launcher.dart';

final _myEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, academyId) {
  return ref.watch(eventsApiProvider).forAcademy(academyId);
});

enum _Tab { upcoming, past }

/// A student's Events: only what is aimed at them (the server filters by audience), split into
/// Upcoming and Past, with an "I'm interested" toggle that stops accepting new interest after the
/// event's deadline.
class StudentEventsScreen extends ConsumerStatefulWidget {
  const StudentEventsScreen({super.key});

  @override
  ConsumerState<StudentEventsScreen> createState() => _State();
}

class _State extends ConsumerState<StudentEventsScreen> {
  _Tab _tab = _Tab.upcoming;
  // Optimistic override of interestedByMe per event, until the next refetch confirms it.
  final Map<String, bool> _interest = {};

  static DateTime _day(String iso) {
    final d = DateTime.tryParse(iso) ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  bool _on(Event e) => _interest[e.id] ?? e.interestedByMe;

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
        showAppToast(context, "Couldn't update — try again");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final membership = ref.watch(sessionControllerProvider).user?.activeMembership;
    final academyId = membership?.academyId;
    if (academyId == null) return const SizedBox.shrink();
    final async = ref.watch(_myEventsProvider(academyId));
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(children: [
          AppTopBar(title: 'Events', subtitle: membership?.academyName),
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
                final shown = _tab == _Tab.upcoming ? upcoming : past;
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_myEventsProvider(academyId)),
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
                    GoldTabs<_Tab>(
                      options: _Tab.values,
                      labelOf: (t) => t == _Tab.upcoming ? 'Upcoming · ${upcoming.length}' : 'Past · ${past.length}',
                      selected: _tab,
                      onTap: (t) => setState(() => _tab = t),
                    ),
                    const SizedBox(height: 14),
                    if (shown.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        alignment: Alignment.center,
                        child: Text(_tab == _Tab.upcoming ? 'No upcoming events' : 'No past events yet',
                            style: TextStyle(fontSize: 12, color: palette.textFaint)),
                      ),
                    for (final e in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EventCard(
                          event: e,
                          interested: _on(e),
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

String _dateLabel(Event e) {
  final s = DateTime.tryParse(e.eventDate);
  if (s == null) return e.eventDate;
  if (!e.isMultiDay) return formatFeeDate(s);
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

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.interested,
    required this.closed,
    required this.onOpen,
    required this.onToggle,
  });

  final Event event;
  final bool interested;
  final bool closed;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _audienceColor(palette, event);
    final cancelled = event.isCancelled;
    final time = _timeLabel(event);
    return Opacity(
      opacity: cancelled ? 0.65 : 1,
      child: InkWell(
        borderRadius: AppRadii.all(AppRadii.xxl),
        onTap: onOpen,
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
              child: Icon(Icons.event_outlined, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: palette.text)),
                  ),
                  if (cancelled) StatusBadge(label: 'CANCELLED', color: palette.notPaid, softColor: palette.notPaidSoft, dense: true),
                ]),
                const SizedBox(height: 3),
                Text(time == null ? _dateLabel(event) : '${_dateLabel(event)} · $time',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textMuted)),
                if ((event.location ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.place_outlined, size: 11, color: palette.textFaint),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(event.location!,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusBadge(label: _audienceLabel(event), color: color, dense: true),
                  if (event.interestedCount > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star, size: 11, color: palette.gold),
                      const SizedBox(width: 3),
                      Text('${event.interestedCount} interested',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: palette.gold)),
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
  const _InterestButton({required this.interested, required this.closed, required this.onTap});
  final bool interested;
  final bool closed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disabled = closed && !interested;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
        borderRadius: AppRadii.all(AppRadii.md),
        onTap: disabled ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: interested ? palette.primary : Colors.transparent,
            borderRadius: AppRadii.all(AppRadii.md),
            border: interested ? null : Border.all(color: palette.border),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(interested ? Icons.star : Icons.star_border, size: 13, color: interested ? palette.onPrimary : palette.textMuted),
            const SizedBox(width: 6),
            Text(interested ? 'Interested' : closed ? 'RSVP closed' : "I'm interested",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: interested ? palette.onPrimary : palette.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.event, required this.interested, required this.closed, required this.onToggle});
  final Event event;
  final bool interested;
  final bool closed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _audienceColor(palette, event);
    final time = _timeLabel(event);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 70, child: Text(k, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textFaint))),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.text))),
          ]),
        );
    final deadline = event.interestDeadline == null ? null : DateTime.tryParse(event.interestDeadline!);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Text(event.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.text))),
          const SizedBox(height: 10),
          Row(children: [
            StatusBadge(label: _audienceLabel(event), color: color),
            const SizedBox(width: 8),
            StatusBadge(label: event.visibility == 'PUBLIC' ? 'Public' : 'In-house', color: palette.textMuted),
            if (event.isCancelled) ...[
              const SizedBox(width: 8),
              StatusBadge(label: 'CANCELLED', color: palette.notPaid, softColor: palette.notPaidSoft),
            ],
          ]),
          if ((event.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(event.description!, style: TextStyle(fontSize: 11.5, height: 1.5, color: palette.textMuted)),
          ],
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: palette.border),
            ),
            child: Column(children: [
              row('Date', _dateLabel(event)),
              if (time != null) row('Time', time),
              if ((event.location ?? '').isNotEmpty) row('Venue', event.location!),
            ]),
          ),
          if ((event.venueMapsUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => launchUrl(Uri.parse(event.venueMapsUrl!), mode: LaunchMode.externalApplication),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.open_in_new, size: 13, color: palette.gateway),
                const SizedBox(width: 6),
                Text('Open in Google Maps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.gateway)),
              ]),
            ),
          ],
          if (deadline != null && !event.isCancelled) ...[
            const SizedBox(height: 12),
            Text(
              closed ? 'Interest can no longer be marked for this event' : 'Interest can be marked until ${formatFeeDate(deadline)}',
              style: TextStyle(fontSize: 11.5, color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          if (event.isCancelled)
            Center(child: Text('This event has been cancelled', style: TextStyle(fontSize: 11, color: palette.textFaint)))
          else
            _InterestButton(interested: interested, closed: closed, onTap: onToggle),
        ]),
      ),
    );
  }
}

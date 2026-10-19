import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/choice_chips.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/events/presentation/event_common.dart';
import 'package:nest_fe/features/events/presentation/event_detail_screen.dart';
import 'package:nest_fe/features/events/presentation/event_form_screen.dart';

/// The Event Creation module's landing page: upcoming/past events, a calendar of what is on which
/// day, and the per-event menu.
class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  String _tab = 'upcoming';
  String _query = '';
  DateTime? _filterDate;

  String get _academyId => ref.read(sessionControllerProvider).user?.activeMembership?.academyId ?? '';

  static bool _isUpcoming(Event e, DateTime today) {
    final end = DateTime.tryParse(e.endDate ?? e.eventDate);
    return end == null || !end.isBefore(DateTime(today.year, today.month, today.day));
  }

  Future<void> _openDetail(Event event) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)));
    ref.invalidate(academyEventsProvider(_academyId));
  }

  Future<void> _openForm({Event? existing}) async {
    await openEventForm(context, existing: existing);
    ref.invalidate(academyEventsProvider(_academyId));
  }

  Future<void> _onMenu(Event event, EventMenuAction action) async {
    switch (action) {
      case EventMenuAction.edit:
        await _openForm(existing: event);
      case EventMenuAction.duplicate:
        await _openForm(existing: duplicateOf(event));
      case EventMenuAction.cancel:
        await confirmAndCancelEvent(context, ref, event);
      case EventMenuAction.restore:
        await setEventStatus(context, ref, event, 'PUBLISHED', 'Event restored.');
      case EventMenuAction.delete:
        await confirmAndDeleteEvent(context, ref, event);
    }
  }

  /// Dots on each calendar day, one per event in that event's audience colour.
  Future<Map<int, CalendarDayMark>> _monthMarks(DateTime month) async {
    final palette = context.palette;
    final categories = ref.read(courseCategoriesProvider);
    final events = await ref.read(academyEventsProvider(_academyId).future);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final marks = <int, CalendarDayMark>{};
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      final dots = [for (final e in events) if (eventCoversDay(e, day)) audienceColor(palette, e, categories)];
      if (dots.isNotEmpty) marks[d] = CalendarDayMark(dots: dots);
    }
    return marks;
  }

  Future<void> _openCalendar() async {
    final base = _filterDate ?? DateTime.now();
    final palette = context.palette;
    final picked = await showAppCalendar(
      context: context,
      month: DateTime(base.year, base.month),
      selectedDay: _filterDate?.day,
      marksLoader: _monthMarks,
      marksKey: [
        CalendarKeyEntry('All students', palette.gold),
        CalendarKeyEntry('All trainers', palette.gateway),
        CalendarKeyEntry('Everyone', palette.coral),
        CalendarKeyEntry('Course / Batch', palette.primary),
        CalendarKeyEntry('Individuals', palette.violet),
      ],
      dayDetailBuilder: _dayEvents,
    );
    if (picked != null) setState(() => _filterDate = picked);
  }

  /// The panel under the calendar grid: that day's events, tap one to open it.
  Widget? _dayEvents(BuildContext dialogContext, DateTime day) {
    final events = ref.read(academyEventsProvider(_academyId)).valueOrNull ?? const <Event>[];
    final onDay = events.where((e) => eventCoversDay(e, day)).toList();
    if (onDay.isEmpty) return null;
    final palette = dialogContext.palette;
    final categories = ref.read(courseCategoriesProvider);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatFeeDate(day), style: TextStyle(fontSize: AppType.base, fontWeight: AppType.heavy, color: palette.text)),
          const SizedBox(height: AppSpacing.md),
          for (final e in onDay)
            Pressable(
              onTap: () {
                Navigator.of(dialogContext).pop();
                _openDetail(e);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
                decoration: BoxDecoration(
                  color: palette.surfaceHigh,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: audienceColor(palette, e, categories).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    _EventTile(color: audienceColor(palette, e, categories), size: 30),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.text)),
                          Text('${formatEventTimeRange(e) ?? 'All day'} · ${audienceLabels[e.audienceType] ?? e.audienceType}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.semi, color: palette.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final academyId = _academyId;
    final eventsAsync = ref.watch(academyEventsProvider(academyId));
    final categories = ref.watch(courseCategoriesProvider);
    final today = DateTime.now();
    final upcomingCount = eventsAsync.valueOrNull?.where((e) => !e.isCancelled && _isUpcoming(e, today)).length;

    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              title: 'Events',
              subtitle: upcomingCount == null ? null : '$upcomingCount upcoming',
              actions: [
                AppIconButton(icon: Icons.calendar_month_outlined, onTap: _openCalendar),
                const ThemeModeButton(),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised,
                        borderRadius: AppRadii.all(AppRadii.lg),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 16, color: palette.textFaint),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              style: TextStyle(color: palette.text),
                              decoration: InputDecoration(
                                hintText: 'Search events',
                                hintStyle: TextStyle(color: palette.textFaint),
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppChoiceChips<String>(
                      options: const ['upcoming', 'past'],
                      labelOf: (v) => v == 'upcoming' ? 'Upcoming' : 'Past',
                      isSelected: (v) => v == _tab,
                      onTap: (v) => setState(() => _tab = v),
                    ),
                    if (_filterDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Pressable(
                            onTap: () => setState(() => _filterDate = null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                              decoration: BoxDecoration(color: palette.primarySoft, borderRadius: AppRadii.all(AppRadii.sm)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(formatFeeDate(_filterDate!),
                                    style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.primary)),
                                const SizedBox(width: AppSpacing.xxs),
                                Icon(Icons.close, size: 12, color: palette.primary),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: AsyncValueView<List<Event>>(
                        value: eventsAsync,
                        onRetry: () => ref.invalidate(academyEventsProvider(academyId)),
                        data: (context, events) {
                          var list = events.where((e) => _tab == 'upcoming' ? _isUpcoming(e, today) : !_isUpcoming(e, today)).toList();
                          if (_filterDate != null) list = list.where((e) => eventCoversDay(e, _filterDate!)).toList();
                          if (_query.trim().isNotEmpty) {
                            final q = _query.trim().toLowerCase();
                            list = list.where((e) => e.title.toLowerCase().contains(q) || (e.location ?? '').toLowerCase().contains(q)).toList();
                          }
                          list.sort((a, b) => _tab == 'upcoming' ? a.eventDate.compareTo(b.eventDate) : b.eventDate.compareTo(a.eventDate));

                          if (list.isEmpty) {
                            return EmptyState(icon: Icons.celebration_outlined, message: 'No $_tab events${_filterDate != null ? ' on this day' : ''}.');
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (context, i) => _EventRow(
                              event: list[i],
                              accent: audienceColor(palette, list[i], categories),
                              onOpen: () => _openDetail(list[i]),
                              onMenu: (action) => _onMenu(list[i], action),
                            ),
                          );
                        },
                      ),
                    ),
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

/// The square calendar tile in an event's audience colour.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.color, this.size = 42});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadii.all(size * 0.28),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(Icons.event_outlined, size: size * 0.43, color: color),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.accent, required this.onOpen, required this.onMenu});

  final Event event;
  final Color accent;
  final VoidCallback onOpen;
  final ValueChanged<EventMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cancelled = event.isCancelled;
    final timeRange = formatEventTimeRange(event);
    final isPublic = event.visibility == 'PUBLIC';

    return Opacity(
      opacity: cancelled ? 0.6 : 1,
      child: Pressable(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.borderSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventTile(color: accent),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
                        ),
                        if (cancelled) ...[const SizedBox(width: AppSpacing.sm), StatusBadge(label: 'CANCELLED', color: palette.notPaid)],
                        if (event.isDraft) ...[const SizedBox(width: AppSpacing.sm), StatusBadge(label: 'DRAFT', color: palette.gold)],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timeRange == null ? formatEventDateRange(event) : '${formatEventDateRange(event)} · $timeRange',
                      style: TextStyle(fontSize: AppType.base, fontWeight: AppType.medium, color: palette.textMuted),
                    ),
                    if (event.location != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.place_outlined, size: 11, color: palette.textFaint),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(event.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                        ),
                      ]),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(label: audienceLabels[event.audienceType] ?? event.audienceType, color: accent),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isPublic ? Icons.public : Icons.home_outlined, size: 11, color: palette.textFaint),
                          const SizedBox(width: 3),
                          Text(isPublic ? 'Public' : 'In-house',
                              style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.textMuted)),
                        ]),
                        if (event.audienceType != 'ALL_TRAINERS')
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.star_outline_rounded, size: 11, color: palette.primary),
                            const SizedBox(width: 3),
                            Text('${event.interestedCount} interested',
                                style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.primary)),
                          ]),
                      ],
                    ),
                  ],
                ),
              ),
              EventMenuButton(cancelled: cancelled, onSelected: onMenu),
            ],
          ),
        ),
      ),
    );
  }
}

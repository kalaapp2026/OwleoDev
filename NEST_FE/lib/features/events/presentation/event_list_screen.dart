import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/calendar_modal.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/events/presentation/event_detail_screen.dart';
import 'package:nest_fe/features/events/presentation/event_form_screen.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;

final _academyEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, academyId) {
  return ref.watch(eventsApiProvider).forAcademy(academyId);
});

const _audienceLabels = {
  'ALL_STUDENTS': 'All students',
  'ALL_TRAINERS': 'All trainers',
  'BY_COURSE': 'By course',
  'BY_BATCH': 'By batch',
  'INDIVIDUALS': 'Individuals',
};

Color _audienceColor(AppPalette palette, String audienceType) => switch (audienceType) {
      'ALL_STUDENTS' => palette.gold,
      'ALL_TRAINERS' => palette.gateway,
      'INDIVIDUALS' => palette.violet,
      _ => palette.primary,
    };

String _formatDateRange(Event e) {
  final start = DateTime.tryParse(e.eventDate);
  if (start == null) return e.eventDate;
  if (!e.isMultiDay) return formatFeeDate(start);
  final end = DateTime.tryParse(e.endDate!);
  return '${formatFeeDate(start)} – ${end == null ? '' : formatFeeDate(end)}';
}

String? _formatTimeRange(Event e) {
  final start = DateTime.tryParse(e.eventDate);
  if (start == null || (start.hour == 0 && start.minute == 0)) return null;
  final label = TimeOfDay.fromDateTime(start).format24();
  final end = e.endDate == null ? null : DateTime.tryParse(e.endDate!);
  if (end == null || (end.hour == 0 && end.minute == 0)) return label;
  return '$label – ${TimeOfDay.fromDateTime(end).format24()}';
}

extension on TimeOfDay {
  String format24() {
    final h = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    final periodLabel = period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:${minute.toString().padLeft(2, '0')} $periodLabel';
  }
}

/// The Event Creation module's real landing page - replaces the old create-form-as-landing-page.
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

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final base = _filterDate ?? now;
    final picked = await showAppCalendar(context: context, month: DateTime(base.year, base.month), selectedDay: _filterDate?.day);
    if (picked != null) setState(() => _filterDate = picked);
  }

  Future<void> _duplicate(Event event) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventFormScreen(
        existing: Event(
          id: '', academyId: event.academyId, type: event.type, title: '${event.title} (Copy)',
          description: event.description, eventDate: event.eventDate, endDate: event.endDate,
          location: event.location, venueMapsUrl: event.venueMapsUrl, visibility: event.visibility,
          coverImageUrl: event.coverImageUrl, interestDeadline: event.interestDeadline, status: 'DRAFT',
          audienceType: event.audienceType, courseIds: event.courseIds, batchIds: event.batchIds,
          individualIds: event.individualIds, invitedCount: 0, interestedCount: 0,
        ),
      ),
    ));
    ref.invalidate(_academyEventsProvider(_academyId));
  }

  Future<void> _setStatus(Event event, String status, String successMessage) async {
    try {
      await ref.read(eventsApiProvider).updateStatus(event.id, status);
      ref.invalidate(_academyEventsProvider(_academyId));
      if (mounted) AppNotice.success(context, successMessage);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _delete(Event event) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete this event?',
      message: '"${event.title}" will be permanently removed. This can\'t be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(eventsApiProvider).delete(event.id);
      ref.invalidate(_academyEventsProvider(_academyId));
      if (mounted) AppNotice.success(context, 'Event deleted.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final academyId = _academyId;
    final eventsAsync = ref.watch(_academyEventsProvider(academyId));
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Events'),
        actions: [IconButton(icon: const Icon(Icons.calendar_month_outlined), onPressed: _openCalendar)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventFormScreen()));
          ref.invalidate(_academyEventsProvider(academyId));
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
      ),
      body: Padding(
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
                  Icon(Icons.search, size: 15, color: palette.textFaint),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(hintText: 'Search events', hintStyle: TextStyle(color: palette.textFaint), border: InputBorder.none, focusedBorder: InputBorder.none, enabledBorder: InputBorder.none, filled: false, isDense: true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppSegmentedControl<String>(
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
                        Text(formatFeeDate(_filterDate!), style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.primary)),
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
                onRetry: () => ref.invalidate(_academyEventsProvider(academyId)),
                data: (context, events) {
                  var list = events.where((e) {
                    final end = e.endDate == null ? DateTime.tryParse(e.eventDate) : DateTime.tryParse(e.endDate!);
                    final isUpcoming = end == null || !end.isBefore(DateTime(today.year, today.month, today.day));
                    return _tab == 'upcoming' ? isUpcoming : !isUpcoming;
                  }).toList();
                  if (_filterDate != null) {
                    final f = _filterDate!;
                    list = list.where((e) {
                      final start = DateTime.tryParse(e.eventDate);
                      final end = e.endDate == null ? start : DateTime.tryParse(e.endDate!);
                      if (start == null) return false;
                      final day = DateTime(f.year, f.month, f.day);
                      return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
                          !day.isAfter(DateTime((end ?? start).year, (end ?? start).month, (end ?? start).day));
                    }).toList();
                  }
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
                      onOpen: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: list[i].id)));
                        ref.invalidate(_academyEventsProvider(academyId));
                      },
                      onEdit: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventFormScreen(existing: list[i])));
                        ref.invalidate(_academyEventsProvider(academyId));
                      },
                      onDuplicate: () => _duplicate(list[i]),
                      onCancel: () => _setStatus(list[i], 'CANCELLED', 'Event cancelled.'),
                      onRestore: () => _setStatus(list[i], 'PUBLISHED', 'Event restored.'),
                      onDelete: () => _delete(list[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.onOpen,
    required this.onEdit,
    required this.onDuplicate,
    required this.onCancel,
    required this.onRestore,
    required this.onDelete,
  });

  final Event event;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onCancel;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = _audienceColor(palette, event.audienceType);
    final cancelled = event.isCancelled;
    final timeRange = _formatTimeRange(event);

    return Opacity(
      opacity: cancelled ? 0.55 : 1,
      child: Pressable(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(event.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
                  ),
                  if (cancelled) ...[const SizedBox(width: AppSpacing.sm), StatusBadge(label: 'CANCELLED', color: palette.notPaid)],
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 18, color: palette.textMuted),
                    onSelected: (v) => switch (v) {
                      'edit' => onEdit(),
                      'duplicate' => onDuplicate(),
                      'cancel' => onCancel(),
                      'restore' => onRestore(),
                      _ => onDelete(),
                    },
                    itemBuilder: (context) => cancelled
                        ? const [
                            PopupMenuItem(value: 'restore', child: Text('Restore event')),
                            PopupMenuItem(value: 'delete', child: Text('Delete event')),
                          ]
                        : const [
                            PopupMenuItem(value: 'edit', child: Text('Edit event')),
                            PopupMenuItem(value: 'duplicate', child: Text('Duplicate event')),
                            PopupMenuItem(value: 'cancel', child: Text('Cancel event')),
                            PopupMenuItem(value: 'delete', child: Text('Delete event')),
                          ],
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                timeRange == null ? _formatDateRange(event) : '${_formatDateRange(event)} · $timeRange',
                style: TextStyle(fontSize: AppType.base, fontWeight: AppType.medium, color: palette.textMuted),
              ),
              if (event.location != null) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.place_outlined, size: 11, color: palette.textFaint),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(child: Text(event.location!, style: TextStyle(fontSize: AppType.sm, color: palette.textFaint))),
                ]),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  StatusBadge(label: _audienceLabels[event.audienceType] ?? event.audienceType, color: accent),
                  StatusBadge(
                    label: event.visibility == 'PUBLIC' ? 'Public' : 'In-house',
                    color: palette.textMuted,
                    softColor: palette.surfaceHigh,
                  ),
                  if (event.isDraft) StatusBadge(label: 'DRAFT', color: palette.gold),
                  if (event.audienceType != 'ALL_TRAINERS')
                    StatusBadge(label: '${event.interestedCount} interested', color: palette.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

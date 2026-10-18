import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;

/// Shared by the Events list, calendar and detail screens, so a date, an audience colour or a
/// cancel/delete behaves identically on each.

final academyEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, academyId) {
  return ref.watch(eventsApiProvider).forAcademy(academyId);
});

/// Course id -> category, so an event for a course can take that course's colour. Empty when the
/// caller can't list courses - the colour then falls back to the neutral accent, never an error.
final courseCategoriesProvider = Provider.autoDispose<Map<String, CourseCategory>>((ref) {
  final courses = ref.watch(allCoursesProvider).valueOrNull;
  return {for (final c in courses ?? const []) c.id: c.category};
});

const audienceLabels = {
  'ALL_STUDENTS': 'All students',
  'ALL_TRAINERS': 'All trainers',
  'BY_COURSE': 'By course',
  'BY_BATCH': 'By batch',
  'INDIVIDUALS': 'Individuals',
};

/// Each audience keeps one colour so a glance down the list shows who an event is for. A course
/// event takes its course's category colour, as the prototype does.
Color audienceColor(AppPalette palette, Event event, Map<String, CourseCategory> courseCategories) {
  switch (event.audienceType) {
    case 'ALL_STUDENTS':
      return palette.gold;
    case 'ALL_TRAINERS':
      return palette.gateway;
    case 'INDIVIDUALS':
      return palette.violet;
    case 'BY_COURSE':
      final category = event.courseIds.isEmpty ? null : courseCategories[event.courseIds.first];
      return category == null ? palette.primary : category.meta(palette).color;
    default:
      return palette.primary;
  }
}

DateTime? _parse(String? iso) => iso == null ? null : DateTime.tryParse(iso);

bool _hasTime(DateTime d) => !(d.hour == 0 && d.minute == 0);

String formatClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// "20 Oct 2026", or "19 Sep 2026 – 20 Sep 2026" for a multi-day event.
String formatEventDateRange(Event e) {
  final start = _parse(e.eventDate);
  if (start == null) return e.eventDate;
  if (!e.isMultiDay) return formatFeeDate(start);
  final end = _parse(e.endDate);
  return '${formatFeeDate(start)} – ${end == null ? '' : formatFeeDate(end)}';
}

/// "5:30 PM – 8:30 PM", or null for an event with no time set.
String? formatEventTimeRange(Event e) {
  final start = _parse(e.eventDate);
  if (start == null || !_hasTime(start)) return null;
  final end = _parse(e.endDate);
  if (end == null || !_hasTime(end)) return formatClock(start);
  return '${formatClock(start)} – ${formatClock(end)}';
}

/// Whether [day] falls inside the event's dates (inclusive). Compares calendar days only.
bool eventCoversDay(Event e, DateTime day) {
  final start = _parse(e.eventDate);
  if (start == null) return false;
  final end = _parse(e.endDate) ?? start;
  final d = DateTime(day.year, day.month, day.day);
  return !d.isBefore(DateTime(start.year, start.month, start.day)) && !d.isAfter(DateTime(end.year, end.month, end.day));
}

/// The form seeded from [source] as a new draft. The empty id is what tells the form it is
/// creating, not editing.
Event duplicateOf(Event source) => Event(
      id: '',
      academyId: source.academyId,
      type: source.type,
      title: '${source.title} (Copy)',
      description: source.description,
      eventDate: source.eventDate,
      endDate: source.endDate,
      location: source.location,
      venueMapsUrl: source.venueMapsUrl,
      visibility: source.visibility,
      coverImageUrl: source.coverImageUrl,
      interestDeadline: source.interestDeadline,
      status: 'DRAFT',
      audienceType: source.audienceType,
      courseIds: source.courseIds,
      batchIds: source.batchIds,
      individualIds: source.individualIds,
      invitedCount: 0,
      interestedCount: 0,
    );

Future<bool> setEventStatus(BuildContext context, WidgetRef ref, Event event, String status, String successMessage) async {
  try {
    await ref.read(eventsApiProvider).updateStatus(event.id, status);
    ref.invalidate(academyEventsProvider(event.academyId));
    if (context.mounted) AppNotice.success(context, successMessage);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppNotice.error(context, e.message);
    return false;
  }
}

/// Confirms, then marks the event cancelled - restorable later, unlike a delete.
Future<bool> confirmAndCancelEvent(BuildContext context, WidgetRef ref, Event event) async {
  final confirmed = await showAppConfirmDialog(
    context: context,
    title: 'Cancel this event?',
    message: '"${event.title}" will be marked cancelled. Anyone who marked interested will still see it as '
        'cancelled - you can restore it later.',
    confirmLabel: 'Cancel event',
    cancelLabel: 'Keep event',
  );
  if (!confirmed || !context.mounted) return false;
  return setEventStatus(context, ref, event, 'CANCELLED', 'Event cancelled.');
}

/// Confirms, then deletes. True only when the event is actually gone.
Future<bool> confirmAndDeleteEvent(BuildContext context, WidgetRef ref, Event event) async {
  final confirmed = await showAppConfirmDialog(
    context: context,
    title: 'Delete this event?',
    message: '"${event.title}" will be permanently removed. This can\'t be undone.',
    confirmLabel: 'Delete',
  );
  if (!confirmed || !context.mounted) return false;
  try {
    await ref.read(eventsApiProvider).delete(event.id);
    ref.invalidate(academyEventsProvider(event.academyId));
    if (context.mounted) AppNotice.success(context, 'Event deleted.');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppNotice.error(context, e.message);
    return false;
  }
}

/// The overflow menu on an event, shared by the list row and the detail card.
enum EventMenuAction { edit, duplicate, cancel, restore, delete }

List<PopupMenuEntry<EventMenuAction>> eventMenuItems(BuildContext context, {required bool cancelled, bool includeEdit = true}) {
  final danger = TextStyle(color: context.palette.notPaid);
  PopupMenuItem<EventMenuAction> item(EventMenuAction a, String label, {bool isDanger = false}) =>
      PopupMenuItem(value: a, child: Text(label, style: isDanger ? danger : null));
  return cancelled
      ? [item(EventMenuAction.restore, 'Restore event'), item(EventMenuAction.delete, 'Delete event', isDanger: true)]
      : [
          if (includeEdit) item(EventMenuAction.edit, 'Edit event'),
          item(EventMenuAction.duplicate, 'Duplicate event'),
          item(EventMenuAction.cancel, 'Cancel event', isDanger: true),
          item(EventMenuAction.delete, 'Delete event', isDanger: true),
        ];
}

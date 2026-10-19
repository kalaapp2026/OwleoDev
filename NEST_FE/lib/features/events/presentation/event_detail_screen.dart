import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/events/presentation/event_common.dart';
import 'package:nest_fe/features/events/presentation/event_form_screen.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;
import 'package:url_launcher/url_launcher.dart';

final _eventProvider = FutureProvider.autoDispose.family<Event, String>((ref, id) {
  return ref.watch(eventsApiProvider).get(id);
});

final _eventInterestsProvider = FutureProvider.autoDispose.family<EventInterests, String>((ref, id) {
  return ref.watch(eventsApiProvider).interestsFor(id);
});

/// Pure ERP admin read view - no "mark interested" affordance, that's a Social/Student action
/// already served by `events_tab.dart`. Shows the real per-user opt-in Interested list and, for a
/// staff event that notifies trainers, which trainers. There is no student roster: the
/// metadata-only scope decision stops at a count on the invited side.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final eventAsync = ref.watch(_eventProvider(eventId));
    final event = eventAsync.valueOrNull;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              title: 'Event',
              subtitle: event == null ? null : (event.isCancelled ? 'Cancelled' : formatEventDateRange(event)),
            ),
            Expanded(
              child: AsyncValueView<Event>(
                value: eventAsync,
                onRetry: () => ref.invalidate(_eventProvider(eventId)),
                data: (context, event) => _Body(event: event),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.event});
  final Event event;

  void _refresh(WidgetRef ref) {
    ref.invalidate(_eventProvider(event.id));
    ref.invalidate(_eventInterestsProvider(event.id));
    ref.invalidate(academyEventsProvider(event.academyId));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Event target) async {
    final result = await openEventForm(context, existing: target);
    if (!context.mounted) return;
    if (result == eventFormDeleted) {
      Navigator.of(context).pop();
      return;
    }
    _refresh(ref);
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, EventMenuAction action) async {
    switch (action) {
      case EventMenuAction.edit:
        await _edit(context, ref, event);
      case EventMenuAction.duplicate:
        await _edit(context, ref, duplicateOf(event));
      case EventMenuAction.cancel:
        if (await confirmAndCancelEvent(context, ref, event)) _refresh(ref);
      case EventMenuAction.restore:
        if (await setEventStatus(context, ref, event, 'PUBLISHED', 'Event restored.')) _refresh(ref);
      case EventMenuAction.delete:
        if (await confirmAndDeleteEvent(context, ref, event) && context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final interestsAsync = ref.watch(_eventInterestsProvider(event.id));
    final accent = audienceColor(palette, event, ref.watch(courseCategoriesProvider));
    final timeRange = formatEventTimeRange(event);
    final isPublic = event.visibility == 'PUBLIC';
    final cancelled = event.isCancelled;
    // Students are who mark interest, so the invited/interested figures only apply when the event
    // reaches students at all.
    final reachesStudents = event.audienceType != 'ALL_TRAINERS';

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x6l),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xxl),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // One expanding slot, not Flexible + Spacer: those two split the free space evenly and
                  // whatever the badge doesn't fill is left empty at the row's end, which pushed the
                  // type label and menu away from the card's right edge.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(label: audienceLabels[event.audienceType] ?? event.audienceType, color: accent),
                    ),
                  ),
                  Icon(isPublic ? Icons.public : Icons.home_outlined, size: 12, color: palette.textFaint),
                  const SizedBox(width: 4),
                  Text(isPublic ? 'Public' : 'In-house',
                      style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textMuted)),
                  const SizedBox(width: AppSpacing.lg),
                  // Edit has its own button below, so the menu skips it here.
                  EventMenuButton(cancelled: cancelled, includeEdit: false, onSelected: (a) => _onMenu(context, ref, a)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(event.title,
                        style: TextStyle(fontSize: 18, fontWeight: AppType.heavy, color: palette.text)),
                  ),
                  if (cancelled) ...[const SizedBox(width: AppSpacing.sm), StatusBadge(label: 'CANCELLED', color: palette.notPaid)],
                  if (event.isDraft) ...[const SizedBox(width: AppSpacing.sm), StatusBadge(label: 'DRAFT', color: palette.gold)],
                ],
              ),
              const SizedBox(height: 4),
              Text(formatEventDateRange(event),
                  style: TextStyle(fontSize: AppType.md, fontWeight: AppType.semi, color: palette.textMuted)),
              if (timeRange != null) ...[
                const SizedBox(height: 2),
                Text(timeRange, style: TextStyle(fontSize: AppType.base, fontWeight: AppType.semi, color: palette.textFaint)),
              ],
              if (event.location != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  Icon(Icons.place_outlined, size: 13, color: palette.textFaint),
                  const SizedBox(width: 5),
                  Expanded(child: Text(event.location!, style: TextStyle(fontSize: AppType.base, color: palette.textMuted))),
                ]),
                if (event.venueMapsUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: GestureDetector(
                      onTap: () => launchUrl(Uri.parse(event.venueMapsUrl!), mode: LaunchMode.externalApplication),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.open_in_new, size: 12, color: palette.primary),
                        const SizedBox(width: 5),
                        Text('Open in Google Maps',
                            style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
                      ]),
                    ),
                  ),
              ],
              if (event.description != null && event.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(event.description!, style: TextStyle(fontSize: AppType.lg, height: 1.55, color: palette.text)),
              ],
            ],
          ),
        ),
        if (!cancelled) ...[
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton(
            onPressed: () => _edit(context, ref, event),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: palette.text,
              backgroundColor: palette.surfaceRaised,
              side: BorderSide(color: palette.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
              textStyle: const TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold),
            ),
            child: const Text('Edit event'),
          ),
        ],
        if (event.interestDeadline != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.lg),
              border: Border.all(color: palette.borderSoft),
            ),
            child: Row(children: [
              Icon(Icons.schedule, size: 13, color: palette.gold),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Interest can be marked until ${formatFeeDate(DateTime.parse(event.interestDeadline!))}',
                    style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
              ),
            ]),
          ),
        ],
        if (reachesStudents) ...[
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: StatBox(label: 'Invited', value: '${event.invitedCount}')),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: StatBox(label: 'Interested', value: '${event.interestedCount}', accent: palette.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.x4l),
          _SectionLabel('Interested students'),
          const SizedBox(height: AppSpacing.sm),
          AsyncValueView<EventInterests>(
            value: interestsAsync,
            onRetry: () => ref.invalidate(_eventInterestsProvider(event.id)),
            data: (context, interests) {
              if (interests.interested.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('No one has marked interested yet.', style: TextStyle(fontSize: AppType.md, color: palette.textFaint)),
                );
              }
              return Column(
                children: [
                  for (final person in interests.interested)
                    _PersonRow(
                      name: person.fullName,
                      seed: person.userId,
                      trailing: Icon(Icons.star_rounded, size: 16, color: palette.primary),
                    ),
                ],
              );
            },
          ),
        ],
        // Whoever the event notifies on the trainer side. The server leaves this empty for a caller
        // who can't manage events, so the section simply doesn't appear for them.
        ...?interestsAsync.valueOrNull?.trainers.isEmpty == false
            ? [
                const SizedBox(height: AppSpacing.x4l),
                _SectionLabel('Trainers notified'),
                const SizedBox(height: AppSpacing.sm),
                for (final t in interestsAsync.value!.trainers) _PersonRow(name: t.fullName, seed: t.membershipId),
              ]
            : null,
        if (!reachesStudents && interestsAsync.valueOrNull?.trainers.isEmpty == true) ...[
          const SizedBox(height: AppSpacing.x4l),
          Center(child: Text('No audience selected for this event yet.', style: TextStyle(fontSize: AppType.smd, color: palette.textFaint))),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: context.palette.textMuted, letterSpacing: 0.5));
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.name, required this.seed, this.trailing});

  final String name;
  final String seed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 4),
      child: Row(
        children: [
          PersonAvatar(name: name, seed: seed, size: 32),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: Text(name, style: TextStyle(fontSize: AppType.lg, color: palette.text))),
          ?trailing,
        ],
      ),
    );
  }
}

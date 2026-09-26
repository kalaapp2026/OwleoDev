import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;
import 'package:url_launcher/url_launcher.dart';

const _audienceLabels = {
  'ALL_STUDENTS': 'All students',
  'ALL_TRAINERS': 'All trainers',
  'BY_COURSE': 'By course',
  'BY_BATCH': 'By batch',
  'INDIVIDUALS': 'Individuals',
};

final _eventProvider = FutureProvider.autoDispose.family<Event, String>((ref, id) {
  return ref.watch(eventsApiProvider).get(id);
});

final _eventInterestsProvider = FutureProvider.autoDispose.family<EventInterests, String>((ref, id) {
  return ref.watch(eventsApiProvider).interestsFor(id);
});

String _formatDateTimeRange(Event e) {
  final start = DateTime.tryParse(e.eventDate);
  if (start == null) return e.eventDate;
  final startHasTime = !(start.hour == 0 && start.minute == 0);
  final startLabel = startHasTime ? '${formatFeeDate(start)} · ${TimeOfDay.fromDateTime(start).format24()}' : formatFeeDate(start);
  if (e.endDate == null) return startLabel;
  final end = DateTime.tryParse(e.endDate!);
  if (end == null) return startLabel;
  final endHasTime = !(end.hour == 0 && end.minute == 0);
  final endLabel = endHasTime ? '${formatFeeDate(end)} · ${TimeOfDay.fromDateTime(end).format24()}' : formatFeeDate(end);
  return '$startLabel  →  $endLabel';
}

extension on TimeOfDay {
  String format24() {
    final h = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    final periodLabel = period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:${minute.toString().padLeft(2, '0')} $periodLabel';
  }
}

/// Pure ERP admin read view - no "mark interested" affordance, that's a Social/Student action
/// already served by `events_tab.dart`. Shows the real per-user opt-in Interested list, but no
/// audience roster: the metadata-only scope decision stops at a count on the invited side.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final eventAsync = ref.watch(_eventProvider(eventId));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Event details')),
      body: AsyncValueView<Event>(
        value: eventAsync,
        onRetry: () => ref.invalidate(_eventProvider(eventId)),
        data: (context, event) => _Body(event: event),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final interestsAsync = ref.watch(_eventInterestsProvider(event.id));
    final accent = switch (event.audienceType) {
      'ALL_STUDENTS' => palette.gold,
      'ALL_TRAINERS' => palette.gateway,
      'INDIVIDUALS' => palette.violet,
      _ => palette.primary,
    };

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(event.title, style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.heavy, color: palette.text)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (event.isCancelled) StatusBadge(label: 'CANCELLED', color: palette.notPaid),
            if (event.isDraft) StatusBadge(label: 'DRAFT', color: palette.gold),
            StatusBadge(label: _audienceLabels[event.audienceType] ?? event.audienceType, color: accent),
            StatusBadge(label: event.visibility == 'PUBLIC' ? 'Public' : 'In-house', color: palette.textMuted, softColor: palette.surfaceHigh),
            StatusBadge(
              label: event.type == 'PROGRAMME' ? 'Programme' : 'Looking for Artist',
              color: palette.textMuted,
              softColor: palette.surfaceHigh,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (event.description != null) ...[
          Text(event.description!, style: TextStyle(fontSize: AppType.base, color: palette.textMuted, height: 1.4)),
          const SizedBox(height: AppSpacing.xxl),
        ],
        _InfoRow(icon: Icons.event_outlined, label: _formatDateTimeRange(event)),
        if (event.location != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.place_outlined,
            label: event.location!,
            trailing: event.venueMapsUrl == null
                ? null
                : TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(event.venueMapsUrl!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Open in Maps'),
                  ),
          ),
        ],
        if (event.interestDeadline != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoRow(icon: Icons.hourglass_bottom, label: 'Interest closes ${formatFeeDate(DateTime.parse(event.interestDeadline!))}'),
        ],
        const SizedBox(height: AppSpacing.xxl),
        Row(
          children: [
            Expanded(child: StatBox(label: 'Invited', value: '${event.invitedCount}')),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: StatBox(label: 'Interested', value: '${event.interestedCount}', accent: palette.primary)),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('Interested', style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textMuted, letterSpacing: 0.5)),
        const SizedBox(height: AppSpacing.sm),
        AsyncValueView<EventInterests>(
          value: interestsAsync,
          onRetry: () => ref.invalidate(_eventInterestsProvider(event.id)),
          data: (context, interests) {
            if (interests.interested.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('No one has marked interest yet.', style: TextStyle(color: palette.textFaint)),
              );
            }
            return Column(
              children: [
                for (final person in interests.interested)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: AppRadii.all(AppRadii.lg),
                      border: Border.all(color: palette.borderSoft),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: palette.primarySoft,
                          backgroundImage: person.profileImageUrl == null ? null : NetworkImage(person.profileImageUrl!),
                          child: person.profileImageUrl == null
                              ? Text(person.fullName.isEmpty ? '?' : person.fullName[0].toUpperCase(), style: TextStyle(color: palette.primary))
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(person.fullName, style: TextStyle(fontSize: AppType.base, color: palette.text))),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 16, color: palette.textFaint),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: TextStyle(fontSize: AppType.base, color: palette.textMuted))),
        ?trailing,
      ],
    );
  }
}

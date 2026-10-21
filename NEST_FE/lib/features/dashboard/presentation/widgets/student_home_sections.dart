import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

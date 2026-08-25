import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/events/data/events_api.dart';

final eventsApiProvider = Provider((ref) => EventsApi(ref.watch(dioClientProvider)));
final publicEventsProvider = FutureProvider.autoDispose((ref) => ref.watch(eventsApiProvider).publicEvents());

/// PRD 3.13: public discovery feed of Programme/Looking-for-Artist events across every academy.
class EventsTab extends ConsumerWidget {
  const EventsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(publicEventsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(publicEventsProvider.future),
      child: AsyncValueView<List<Event>>(
        value: events,
        onRetry: () => ref.invalidate(publicEventsProvider),
        data: (context, list) {
          if (list.isEmpty) {
            return ListView(children: const [EmptyState(icon: Icons.celebration_outlined, message: 'No public events right now.')]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _EventCard(event: list[index]),
          );
        },
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    event.type == 'LOOKING_FOR_ARTIST' ? 'LOOKING FOR ARTIST' : 'PROGRAMME',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colorScheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(event.title, style: Theme.of(context).textTheme.titleMedium),
            if (event.description != null) ...[
              const SizedBox(height: 4),
              Text(event.description!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 15, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(event.eventDate, style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.read(eventsApiProvider).markInterested(event.id),
                  child: Text(AppLocalizations.of(context).socInterested),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

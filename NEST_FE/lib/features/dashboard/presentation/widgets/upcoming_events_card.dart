import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/events/data/event.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart' show eventsApiProvider;

final _academyEventsProvider = FutureProvider.autoDispose.family<List<Event>, String>((ref, academyId) {
  return ref.watch(eventsApiProvider).forAcademy(academyId);
});

/// The next few events on the active academy's calendar. Tapping one opens its details inline -
/// there's no Event Detail screen yet, so this stays a bottom sheet rather than a route.
class UpcomingEventsCard extends ConsumerWidget {
  const UpcomingEventsCard({super.key, required this.academyId});

  final String academyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final eventsAsync = ref.watch(_academyEventsProvider(academyId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming events',
          style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text),
        ),
        const SizedBox(height: AppSpacing.md),
        AsyncValueView<List<Event>>(
          value: eventsAsync,
          onRetry: () => ref.invalidate(_academyEventsProvider(academyId)),
          data: (context, events) {
            final now = DateTime.now();
            final upcoming = events.where((e) {
              final date = DateTime.tryParse(e.eventDate);
              return date != null && date.isAfter(now);
            }).toList()
              ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

            if (upcoming.isEmpty) {
              return Text(
                'No upcoming events.',
                style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
              );
            }

            return SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: upcoming.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) => _EventCard(event: upcoming[i]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final date = DateTime.tryParse(event.eventDate);

    return Pressable(
      onTap: () => _showEventDetails(context, event),
      borderRadius: AppRadii.all(AppRadii.xxl),
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xxl),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date != null)
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: palette.violetSoft, borderRadius: AppRadii.all(AppRadii.lg)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${date.day}',
                        style: TextStyle(fontSize: AppType.md, fontWeight: AppType.heavy, color: palette.violet, height: 1)),
                    Text(monthsShort[date.month - 1],
                        style: TextStyle(fontSize: AppType.micro, fontWeight: AppType.bold, color: palette.violet)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.text),
              ),
            ),
            if (event.location != null)
              Text(
                event.location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint),
              ),
          ],
        ),
      ),
    );
  }
}

void _showEventDetails(BuildContext context, Event event) {
  final palette = context.palette;
  final date = DateTime.tryParse(event.eventDate);
  showModalBottomSheet(
    context: context,
    backgroundColor: palette.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x4l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.text)),
          const SizedBox(height: AppSpacing.sm),
          if (date != null)
            Row(children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: palette.textFaint),
              const SizedBox(width: AppSpacing.xs),
              Text(formatFeeDate(date), style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
              const SizedBox(width: AppSpacing.md),
              Text('${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
            ]),
          if (event.location != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(children: [
              Icon(Icons.place_outlined, size: 14, color: palette.textFaint),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(event.location!, style: TextStyle(fontSize: AppType.base, color: palette.textMuted))),
            ]),
          ],
          if (event.description != null && event.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(event.description!, style: TextStyle(fontSize: AppType.base, color: palette.text, height: 1.5)),
          ],
        ],
      ),
    ),
  );
}

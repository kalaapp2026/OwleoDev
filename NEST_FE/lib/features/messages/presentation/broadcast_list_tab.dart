import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/messages/data/broadcast.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/broadcast_detail_screen.dart';
import 'package:nest_fe/features/messages/presentation/widgets/messages_common.dart';

/// The Broadcasts tab: SENT and READ RATE, then every broadcast the academy has sent, newest first.
class BroadcastListTab extends ConsumerWidget {
  const BroadcastListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final broadcastsAsync = ref.watch(sentBroadcastsProvider);

    return AsyncValueView<List<Broadcast>>(
      value: broadcastsAsync,
      onRetry: () => ref.invalidate(sentBroadcastsProvider),
      data: (context, broadcasts) {
        if (broadcasts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_outlined, size: 28, color: palette.textFaint),
                  const SizedBox(height: AppSpacing.md),
                  Text('No broadcasts sent yet. Tap + to reach your students or trainers.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.md, color: palette.textFaint)),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.refresh(sentBroadcastsProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.x6l * 3),
            children: [
              _StatsRow(broadcasts: broadcasts),
              const SizedBox(height: AppSpacing.md),
              for (final b in broadcasts) _BroadcastRow(broadcast: b),
            ],
          ),
        );
      },
    );
  }
}

/// SENT count and READ RATE across every broadcast that has read tracking.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.broadcasts});

  final List<Broadcast> broadcasts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tracked = broadcasts.where((b) => b.readCount != null && b.recipientCount > 0);
    final delivered = tracked.fold<int>(0, (sum, b) => sum + b.recipientCount);
    final read = tracked.fold<int>(0, (sum, b) => sum + b.readCount!);
    final rate = delivered == 0 ? null : (read * 100 / delivered).round();

    Widget card(String value, String label, Color color, Color soft) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 22, fontWeight: AppType.heavy, color: color, height: 1.1)),
                const SizedBox(height: 2),
                Text(label.toUpperCase(),
                    style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, letterSpacing: 0.5, color: color)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        card('${broadcasts.length}', 'Sent', palette.gold, palette.goldSoft),
        const SizedBox(width: AppSpacing.lg),
        card(rate == null ? '—' : '$rate%', 'Read rate', palette.primary, palette.primarySoft),
      ],
    );
  }
}

class _BroadcastRow extends StatelessWidget {
  const _BroadcastRow({required this.broadcast});

  final Broadcast broadcast;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = audienceTone(palette, broadcast.audienceType);
    final reached = 'Sent to ${broadcast.recipientCount}'
        '${broadcast.readCount == null ? '' : ' · ${broadcast.readCount} read'}';

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BroadcastDetailScreen(broadcastId: broadcast.id))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.borderSoft))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.soft,
                border: Border.all(color: tone.color.withValues(alpha: 0.4)),
              ),
              child: Icon(broadcast.audienceType == 'INDIVIDUALS' ? Icons.person_outline : Icons.campaign_outlined,
                  size: 18, color: tone.color),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
                          decoration: BoxDecoration(color: tone.soft, borderRadius: AppRadii.all(AppRadii.sm)),
                          child: Text(audienceLabelOf(broadcast),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.heavy, color: tone.color)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(longAgo(broadcast.createdAt),
                          style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: palette.textFaint)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(broadcast.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppType.md, color: palette.text, height: 1.4)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(reached, style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

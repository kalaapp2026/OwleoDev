import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/messages/data/broadcast.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/broadcast_compose_screen.dart';

const _audienceLabels = {
  'ALL_STUDENTS': 'All students',
  'ALL_TRAINERS': 'All trainers',
  'BY_COURSE': 'By course',
  'BY_BATCH': 'By batch',
  'INDIVIDUALS': 'Individuals',
};

const _audienceIcons = {
  'ALL_STUDENTS': Icons.campaign_outlined,
  'ALL_TRAINERS': Icons.campaign_outlined,
  'BY_COURSE': Icons.campaign_outlined,
  'BY_BATCH': Icons.campaign_outlined,
  'INDIVIDUALS': Icons.person_outline,
};

/// Each audience keeps one colour so a glance down the list shows who a message went to.
({Color color, Color soft}) _audienceTone(AppPalette palette, String audienceType) => switch (audienceType) {
      'ALL_TRAINERS' => (color: palette.gateway, soft: palette.gatewaySoft),
      'BY_COURSE' => (color: palette.primary, soft: palette.primarySoft),
      'BY_BATCH' => (color: palette.gold, soft: palette.goldSoft),
      'INDIVIDUALS' => (color: palette.violet, soft: palette.violetSoft),
      _ => (color: palette.gold, soft: palette.goldSoft),
    };

String _ago(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

/// Messages: an Academy Admin's broadcast history plus the compose affordance. Recipients see
/// what was sent in their existing notification bell - this screen is the sender's own view.
class MessagesHomeScreen extends ConsumerWidget {
  const MessagesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final broadcastsAsync = ref.watch(sentBroadcastsProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastComposeScreen())),
        tooltip: 'New message',
        backgroundColor: palette.gold,
        foregroundColor: palette.onGold,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: 'Messages', actions: const [ThemeModeButton()]),
            Expanded(
              child: AsyncValueView<List<Broadcast>>(
                value: broadcastsAsync,
                onRetry: () => ref.invalidate(sentBroadcastsProvider),
                data: (context, broadcasts) {
                  if (broadcasts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No messages sent yet. Tap + to reach your students or trainers.',
                            textAlign: TextAlign.center, style: TextStyle(color: palette.textMuted)),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.x6l * 2),
                    children: [
                      _StatsRow(broadcasts: broadcasts),
                      const SizedBox(height: AppSpacing.xl),
                      for (final b in broadcasts) _BroadcastRow(broadcast: b),
                    ],
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
    final tone = _audienceTone(palette, broadcast.audienceType);
    final icon = _audienceIcons[broadcast.audienceType] ?? Icons.campaign_outlined;
    final audienceLabel = _audienceLabels[broadcast.audienceType] ?? broadcast.audienceType;
    final reached = 'Sent to ${broadcast.recipientCount}'
        '${broadcast.readCount == null ? '' : ' · ${broadcast.readCount} read'}';

    return Container(
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
            child: Icon(icon, size: 18, color: tone.color),
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
                        child: Text(audienceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.heavy, color: tone.color)),
                      ),
                    ),
                    const Spacer(),
                    Text(_ago(broadcast.createdAt),
                        style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: palette.textMuted)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(broadcast.title,
                    style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.heavy, color: palette.text)),
                const SizedBox(height: 2),
                Text(broadcast.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.md, color: palette.text, height: 1.35)),
                const SizedBox(height: AppSpacing.md),
                Text(reached,
                    style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

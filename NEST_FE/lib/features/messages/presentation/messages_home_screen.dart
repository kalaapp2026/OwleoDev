import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
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
  'ALL_STUDENTS': Icons.groups_outlined,
  'ALL_TRAINERS': Icons.badge_outlined,
  'BY_COURSE': Icons.auto_stories_outlined,
  'BY_BATCH': Icons.grid_view_outlined,
  'INDIVIDUALS': Icons.person_outline,
};

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
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastComposeScreen())),
        backgroundColor: palette.primary,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('New Message'),
      ),
      body: AsyncValueView<List<Broadcast>>(
        value: broadcastsAsync,
        onRetry: () => ref.invalidate(sentBroadcastsProvider),
        data: (context, broadcasts) {
          if (broadcasts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No messages sent yet. Tap "New Message" to reach your students or trainers.',
                    textAlign: TextAlign.center, style: TextStyle(color: palette.textMuted)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.x6l * 2),
            itemCount: broadcasts.length,
            itemBuilder: (context, i) => _BroadcastTile(broadcast: broadcasts[i]),
          );
        },
      ),
    );
  }
}

class _BroadcastTile extends StatelessWidget {
  const _BroadcastTile({required this.broadcast});
  final Broadcast broadcast;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = _audienceIcons[broadcast.audienceType] ?? Icons.campaign_outlined;
    final audienceLabel = _audienceLabels[broadcast.audienceType] ?? broadcast.audienceType;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(broadcast.title, style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(broadcast.body, style: TextStyle(fontSize: AppType.md, color: palette.textMuted), maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _pill(palette, audienceLabel),
              const SizedBox(width: AppSpacing.sm),
              _pill(palette, '${broadcast.recipientCount} reached'),
              const Spacer(),
              if (broadcast.createdAt.isNotEmpty)
                Text(broadcast.createdAt.split('T').first, style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(AppPalette palette, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
      decoration: BoxDecoration(color: palette.primarySoft, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Text(text, style: TextStyle(fontSize: AppType.tiny, color: palette.primary, fontWeight: AppType.medium)),
    );
  }
}

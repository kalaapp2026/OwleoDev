import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/messages/data/broadcast.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/messages/presentation/widgets/messages_common.dart';

/// One sent broadcast: the message, how many people it reached and read it, and the per-person
/// list. A broadcast sent before read tracking existed has no per-person record, and says so.
class BroadcastDetailScreen extends ConsumerWidget {
  const BroadcastDetailScreen({super.key, required this.broadcastId});

  final String broadcastId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final detailAsync = ref.watch(broadcastDetailProvider(broadcastId));

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(title: 'Broadcast', subtitle: detailAsync.valueOrNull == null ? null : longAgo(detailAsync.value!.broadcast.createdAt)),
            Expanded(
              child: AsyncValueView<BroadcastDetail>(
                value: detailAsync,
                onRetry: () => ref.invalidate(broadcastDetailProvider(broadcastId)),
                data: (context, detail) => _Body(detail: detail),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});

  final BroadcastDetail detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final b = detail.broadcast;
    final tone = audienceTone(palette, b.audienceType);
    final tracked = b.readCount != null;

    Widget stat(String value, String label, Color color, Color soft, {bool outlined = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: AppRadii.all(AppRadii.xl),
              border: Border.all(color: outlined ? palette.border : color.withValues(alpha: 0.27)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: AppType.heavy, color: outlined ? palette.text : color)),
                Text(label.toUpperCase(),
                    style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: outlined ? palette.textMuted : color)),
              ],
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x6l),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
                decoration: BoxDecoration(color: tone.soft, borderRadius: AppRadii.all(AppRadii.sm)),
                child: Text(audienceLabelOf(b),
                    style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.heavy, color: tone.color)),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(b.body, style: TextStyle(fontSize: AppType.xl, height: 1.55, color: palette.text)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            stat('${b.recipientCount}', 'Delivered', palette.text, palette.surfaceRaised, outlined: true),
            const SizedBox(width: AppSpacing.lg),
            stat(tracked ? '${b.readCount}' : '—', 'Read', palette.primary, palette.primarySoft),
          ],
        ),
        const SizedBox(height: AppSpacing.x4l),
        Text('RECIPIENTS',
            style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, letterSpacing: 0.6, color: palette.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        if (detail.recipients.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              tracked
                  ? 'No one to show.'
                  : 'This was sent before read tracking, so there is no per-person list for it.',
              style: TextStyle(fontSize: AppType.md, color: palette.textFaint),
            ),
          )
        else
          for (final r in detail.recipients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  PersonAvatar(name: r.name, seed: r.membershipId, size: 32),
                  const SizedBox(width: AppSpacing.lg),
                  Flexible(
                    child: Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppType.lg, color: palette.text)),
                  ),
                  if (r.isTrainer) ...[const SizedBox(width: 6), const TrainerTag()],
                  const Spacer(),
                  Icon(r.read ? Icons.done_all : Icons.check, size: 16, color: r.read ? palette.primary : palette.textFaint),
                ],
              ),
            ),
      ],
    );
  }
}

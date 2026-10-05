import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart';

final _trainerCardProvider = FutureProvider.autoDispose.family<TrainerCard, String>((ref, membershipId) {
  return ref.watch(academyProfileApiProvider).getTrainerCard(membershipId);
});

/// The featured-trainer drill-down: the public-safe account page for a person the Admin chose to
/// feature - avatar, role, designation, the courses they teach, and tap-to-call / email /
/// WhatsApp.
class TrainerCardScreen extends ConsumerWidget {
  const TrainerCardScreen({super.key, required this.membershipId, this.designation});

  final String membershipId;

  /// The Admin's label from the profile; falls back to the person's own qualification.
  final String? designation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(_trainerCardProvider(membershipId));
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            const AppTopBar(title: 'Trainer Profile', subtitle: 'Owleo N.E.S.T. account'),
            Expanded(
              child: AsyncValueView<TrainerCard>(
                value: cardAsync,
                onRetry: () => ref.invalidate(_trainerCardProvider(membershipId)),
                data: (context, card) {
                  final subtitle = designation ?? card.qualification;
                  final isAdmin = card.role == 'ACADEMY_ADMIN';
                  final joinedYear = card.joiningDate?.split('-').first;
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.page),
                    children: [
                      const SizedBox(height: AppSpacing.xxs),
                      Center(child: PersonAvatar(name: card.fullName, seed: card.membershipId, size: 76)),
                      const SizedBox(height: AppSpacing.md),
                      Text(card.fullName,
                          textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.text)),
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                          decoration: BoxDecoration(color: palette.goldSoft, borderRadius: AppRadii.all(AppRadii.sm)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.workspace_premium_outlined, size: 12, color: palette.gold),
                            const SizedBox(width: AppSpacing.xs),
                            Text(isAdmin ? 'ADMIN & TRAINER' : 'TRAINER',
                                style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.heavy, color: palette.gold, letterSpacing: 0.4)),
                          ]),
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
                      ],
                      const SizedBox(height: AppSpacing.x3l),
                      if (card.courseNames.isNotEmpty) ...[
                        _Card(
                          title: 'Specializes in',
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final c in card.courseNames)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: AppSpacing.xs),
                                  decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.sm)),
                                  child: Text(c, style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.text)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x3l),
                      ],
                      if (card.phone != null || card.email != null)
                        _Card(
                          title: 'Contact',
                          child: Column(children: [
                            if (card.phone != null)
                              ContactLinkRow(icon: Icons.call_outlined, caption: 'Tap to call', value: card.phone!, uri: telUri(card.phone!)),
                            if (card.email != null)
                              ContactLinkRow(
                                  icon: Icons.mail_outline, caption: 'Tap to email', value: card.email!, uri: Uri(scheme: 'mailto', path: card.email)),
                            if (card.phone != null)
                              ContactLinkRow(
                                icon: Icons.chat_outlined,
                                caption: 'Tap to chat',
                                value: 'Message on WhatsApp',
                                uri: whatsappUri(card.phone!),
                                color: palette.paidManual,
                              ),
                          ]),
                        ),
                      if (joinedYear != null) ...[
                        const SizedBox(height: AppSpacing.x3l),
                        Text('Trainer since $joinedYear',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                      ],
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

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.borderSoft), borderRadius: AppRadii.all(AppRadii.xxl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.heavy, color: palette.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart' show academyProfileApiProvider;
import 'package:url_launcher/url_launcher.dart';

final _trainerCardProvider = FutureProvider.autoDispose.family<TrainerCard, String>((ref, membershipId) {
  return ref.watch(academyProfileApiProvider).getTrainerCard(membershipId);
});

Future<void> _launch(BuildContext context, Uri uri) async {
  if (!await launchUrl(uri)) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that.')));
  }
}

/// The featured-trainer drill-down: photo, name, designation/qualification, and tap-to-call /
/// tap-to-email / WhatsApp - the public-safe subset a person the Admin has chosen to feature is
/// shown to the rest of the academy.
class TrainerCardScreen extends ConsumerWidget {
  const TrainerCardScreen({super.key, required this.membershipId, this.designation});

  final String membershipId;

  /// Passed in from the featured-trainer chip so it shows instantly rather than waiting on the
  /// card to load; falls back to the card's own `qualification` once it arrives.
  final String? designation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(_trainerCardProvider(membershipId));
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Trainer Profile')),
      body: AsyncValueView<TrainerCard>(
        value: cardAsync,
        onRetry: () => ref.invalidate(_trainerCardProvider(membershipId)),
        data: (context, card) {
          final subtitle = designation ?? card.qualification;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Center(child: PersonAvatar(name: card.fullName, seed: card.membershipId, size: 96)),
              const SizedBox(height: AppSpacing.xl),
              Text(card.fullName,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.display, fontWeight: AppType.heavy, color: palette.text)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
              ],
              if (card.joiningDate != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text('With us since ${card.joiningDate!.split('-').first}',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.base, color: palette.textFaint)),
              ],
              const SizedBox(height: AppSpacing.x5l),
              if (card.phone != null)
                _ContactTile(
                  icon: Icons.call_outlined,
                  label: 'Tap to call',
                  value: card.phone!,
                  onTap: () => _launch(context, Uri(scheme: 'tel', path: card.phone)),
                ),
              if (card.email != null)
                _ContactTile(
                  icon: Icons.mail_outline,
                  label: 'Tap to email',
                  value: card.email!,
                  onTap: () => _launch(context, Uri(scheme: 'mailto', path: card.email)),
                ),
              if (card.phone != null)
                _ContactTile(
                  icon: Icons.chat_outlined,
                  label: 'Message on WhatsApp',
                  value: card.phone!,
                  color: palette.paidManual,
                  onTap: () => _launch(context, Uri.parse('https://wa.me/${card.phone!.replaceAll(RegExp(r'[^0-9]'), '')}')),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.label, required this.value, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = color ?? palette.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.lg)),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: fg.withValues(alpha: 0.1), borderRadius: AppRadii.all(9)),
                child: Icon(icon, size: 14, color: fg),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label.toUpperCase(), style: TextStyle(fontSize: AppType.micro, fontWeight: AppType.bold, color: palette.textMuted, letterSpacing: 0.4)),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: fg)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

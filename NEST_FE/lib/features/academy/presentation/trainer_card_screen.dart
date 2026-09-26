import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/core/widgets/avatar.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Trainer Profile')),
      body: AsyncValueView<TrainerCard>(
        value: cardAsync,
        onRetry: () => ref.invalidate(_trainerCardProvider(membershipId)),
        data: (context, card) {
          final subtitle = designation ?? card.qualification;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Avatar(name: card.fullName, imageUrl: card.profileImageUrl, radius: 48)),
              const SizedBox(height: 14),
              Text(card.fullName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
              if (card.joiningDate != null) ...[
                const SizedBox(height: 4),
                Text('With us since ${card.joiningDate!.split('-').first}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 24),
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
  const _ContactTile({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

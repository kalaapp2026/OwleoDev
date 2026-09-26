import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_billing_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_billing_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart' show academyProfileProvider;
import 'package:nest_fe/features/academy/presentation/change_password_screen.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/profile/presentation/user_settings_screen.dart';

/// The Academy Admin's own settings home. Deliberately smaller than the reference design: this
/// app has no academy-owned login, ownership-transfer workflow, data export, or support inbox to
/// wire up, so those cards are left out entirely rather than shown with nothing behind them. What
/// ships is real: the academy's own identity/plan, the admin's own account password, and their
/// academy's real invoice history.
class AcademySettingsScreen extends ConsumerWidget {
  const AcademySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = ref.watch(sessionControllerProvider).user;
    final membership = user?.activeMembership;

    if (user == null || membership == null || !user.isActiveAcademyAdmin) {
      return const Scaffold(body: Center(child: Text('Academy Admin access required.')));
    }

    final academyId = membership.academyId;
    final profileAsync = ref.watch(academyProfileProvider);
    final detailAsync = ref.watch(academyDetailProvider(academyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Academy Settings')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(academyProfileProvider);
          ref.invalidate(academyDetailProvider(academyId));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncValueView<AcademyProfile>(
              value: profileAsync,
              onRetry: () => ref.invalidate(academyProfileProvider),
              data: (context, profile) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                        backgroundImage: profile.logoUrl != null ? NetworkImage(profile.logoUrl!) : null,
                        child: profile.logoUrl == null
                            ? Text(
                                profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colorScheme.primary),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.name, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            detailAsync.maybeWhen(
                              data: (a) => Text(
                                a.plan != null ? '${a.plan} plan' : 'No plan set',
                                style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                              ),
                              orElse: () => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Login Password'),
                    subtitle: const Text('Change your own account password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.credit_card_outlined),
                    title: const Text('Billing & Subscription'),
                    subtitle: const Text('Current plan and invoice history'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AcademyBillingScreen(academyId: academyId)),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Preferences'),
                    subtitle: const Text('Theme and display language'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

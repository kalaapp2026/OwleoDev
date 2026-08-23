import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/features/profile/presentation/user_settings_screen.dart';
import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/presentation/academy_management_screen.dart';
import 'package:nest_fe/features/artist_application/presentation/artist_applications_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
            child: Text(
              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text(user.fullName, style: Theme.of(context).textTheme.titleLarge)),
        Center(
          child: Text('@${user.username}',
              style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.55), fontSize: 13)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Chip(
            label: Text(user.role.replaceAll('_', ' ')),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 28),

        if (user.isSuperAdmin) ...[
          _SectionLabel(t.profileSuperAdmin),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(t.navAcademies),
              subtitle: const Text('Onboard, suspend or reactivate academies'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AcademyManagementScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Artist Applications'),
              subtitle: const Text('Review Guests applying to become Artists'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArtistApplicationsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (user.isGuest) ...[
          const _SectionLabel('Artist'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Become an Artist'),
              subtitle: const Text('Apply for approval to post to the feed'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/become-artist'),
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (user.activeMemberships.isNotEmpty) ...[
          _SectionLabel(t.profileAcademyMemberships),
          ...user.activeMemberships.map((m) => Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(m.academyName ?? m.academyId),
                  subtitle: Text('${m.roleType.replaceAll('_', ' ')} · ${m.status}'),
                  trailing: m.membershipId == user.activeMembershipId
                      ? Icon(Icons.check_circle, color: colorScheme.primary, size: 20)
                      : null,
                  onTap: () => ref.read(sessionControllerProvider.notifier).switchActiveMembership(m.membershipId),
                ),
              )),
          const SizedBox(height: 20),
        ],

        // Theme and language now share one Settings screen rather than the theme radios sitting
        // inline here - a second full radio list for 12 languages would swamp the profile.
        _SectionLabel(t.settingsTitle),
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: Text(t.settingsTitle),
            subtitle: Text('${t.settingsTheme} · ${t.settingsLanguage}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 28),

        OutlinedButton.icon(
          onPressed: () async {
            final confirmed = await AppNotice.confirm(
              context,
              title: t.authLogOutConfirmTitle,
              message: t.authLogOutConfirmMessage,
              confirmLabel: t.authLogOut,
            );
            if (confirmed) await ref.read(sessionControllerProvider.notifier).logout();
          },
          icon: Icon(Icons.logout, color: colorScheme.error),
          label: Text(t.authLogOut, style: TextStyle(color: colorScheme.error)),
          style: OutlinedButton.styleFrom(side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4))),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

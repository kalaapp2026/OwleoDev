import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/i18n/app_languages.dart';
import 'package:nest_fe/app/i18n/locale_controller.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/security/app_lock.dart';
import 'package:nest_fe/features/profile/presentation/settings_sections.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/presentation/change_password_screen.dart';
import 'package:nest_fe/l10n/app_localizations.dart';

/// Per-user preferences: theme and UI language. Both are stored on the account rather than the
/// device, so they follow the person to whatever they next sign in on.
class UserSettingsScreen extends ConsumerWidget {
  const UserSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(localeProvider);
    // Students can also change their login email (verified by a code sent to the new address).
    final isStudent =
        ref.watch(sessionControllerProvider).user?.activeMembership?.roleType ==
        'STUDENT';
    final lock = ref.watch(appLockProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionLabel(t.settingsAppearance),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (m) =>
                  ref.read(themeModeProvider.notifier).setThemeMode(m!),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text(t.settingsThemeSystem),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text(t.settingsThemeLight),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text(t.settingsThemeDark),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel(t.settingsLanguage),
          Text(
            t.settingsLanguageSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: AppLanguage.values.map((option) {
                final selected = option == language;
                return ListTile(
                  // Native name first - someone hunting for their own language scans for "தமிழ்",
                  // not "Tamil". The English name stays as a subtitle so a support person helping
                  // them can still identify the row.
                  title: Text(
                    option.nativeName,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  subtitle: option.englishName == option.nativeName
                      ? null
                      : Text(option.englishName),
                  trailing: selected
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  onTap: selected
                      ? null
                      : () async {
                          await ref
                              .read(localeProvider.notifier)
                              .setLanguage(option);
                          if (context.mounted) {
                            // Read the string AFTER the switch so the confirmation itself appears
                            // in the language just chosen.
                            AppNotice.success(
                              context,
                              AppLocalizations.of(context).languageChanged,
                            );
                          }
                        },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          const _SectionLabel('Account & security'),
          Card(
            child: Column(
              children: [
                if (isStudent)
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('Login email'),
                    subtitle: const Text(
                      'Change the email your sign-in codes go to',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangeEmailScreen(),
                      ),
                    ),
                  ),
                if (isStudent) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  subtitle: const Text('Change your account password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.pin_outlined),
                  title: const Text('App Lock'),
                  subtitle: Text(
                    lock.hasPin
                        ? 'Unlock with a 4-digit PIN on this device'
                        : 'Off',
                  ),
                  value: lock.hasPin,
                  onChanged: (on) async {
                    if (on) {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const PinSetupScreen(),
                        ),
                      );
                    } else {
                      final ok = await showAppConfirmDialog(
                        context: context,
                        title: 'Turn off App Lock?',
                        message:
                            "You won't need a PIN to open Owleo N.E.S.T. on this device anymore.",
                        confirmLabel: 'Turn off',
                        cancelLabel: 'Cancel',
                      );
                      if (ok) await ref.read(appLockProvider.notifier).clear();
                    }
                  },
                ),
                if (lock.hasPin) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const PinSetupScreen()),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          const _SectionLabel('Notifications'),
          const NotificationPrefsCard(),
          const SizedBox(height: 24),

          const _SectionLabel('Support'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & FAQ'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _HelpScreen()),
                  ),
                ),
                const Divider(height: 1),
                if (isStudent) ...[
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Contact your academy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ContactUsScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About Owleo'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Owleo N.E.S.T.',
                    applicationVersion: '1.0.0',
                    children: const [
                      Text(
                        'Your academy, your courses, attendance and fees - all in one place.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          OutlinedButton.icon(
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Log out'),
            onPressed: () async {
              final ok = await showAppConfirmDialog(
                context: context,
                title: 'Log out of Owleo?',
                message:
                    "You'll need to sign in again to view your courses, attendance and fees.",
                confirmLabel: 'Log out',
                cancelLabel: 'Cancel',
              );
              if (!ok) return;
              // The PIN guards this device for this person - it must not outlive their session.
              await ref.read(appLockProvider.notifier).clear();
              await ref.read(sessionControllerProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
          if (isStudent) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                'Request account deletion',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: () async {
                final ok = await showAppConfirmDialog(
                  context: context,
                  title: 'Request account deletion?',
                  message:
                      "Your records sit under your academy, so deletion has to be approved by your academy admin. We'll send them a request on your behalf.",
                  confirmLabel: 'Send request',
                  cancelLabel: 'Cancel',
                );
                if (!ok) return;
                try {
                  final created = await ref
                      .read(authApiProvider)
                      .requestAccountDeletion();
                  if (context.mounted) {
                    AppNotice.success(
                      context,
                      created
                          ? 'Deletion request sent to your academy admin'
                          : 'You already have a request pending',
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppNotice.error(
                      context,
                      e.toString().replaceFirst('Exception: ', ''),
                    );
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpScreen extends StatelessWidget {
  const _HelpScreen();

  static const _faqs = [
    (
      'How do I check my attendance?',
      'Open the Attendance tab to see your overview, calendar and history, along with your overall percentage.',
    ),
    (
      'How do I see my fees?',
      'The Fees tab lists what is due and what you have paid. Payments are recorded by your academy.',
    ),
    (
      'Can I switch between academies?',
      'Yes - if you are enrolled at more than one academy, use the academy switcher at the top of your dashboard.',
    ),
    (
      'Who do I contact if my details are wrong?',
      "Reach out to your academy's admin - they manage enrolment details like your batch, courses and guardian information.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final f in _faqs)
            Card(
              child: ExpansionTile(
                title: Text(
                  f.$1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(f.$2)],
              ),
            ),
        ],
      ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/i18n/locale_controller.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/security/app_lock.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';
import 'package:nest_fe/features/academy/presentation/academy_support_screens.dart' show AboutOwleoScreen;
import 'package:nest_fe/features/academy/presentation/change_password_screen.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart' show selfProfileProvider;
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart' show PhotoAvatar;
import 'package:nest_fe/features/profile/presentation/settings_sections.dart';
import 'package:nest_fe/l10n/app_localizations.dart';

/// Per-user preferences: theme and UI language (stored on the account, so they follow the person to
/// whatever they next sign in on), login details, app lock, notification switches, support, and
/// the way out. Laid out like the reference's Settings.
class UserSettingsScreen extends ConsumerWidget {
  const UserSettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Log out of Owleo?',
      message: "You'll need to sign in again to view your courses, attendance and fees.",
      confirmLabel: 'Log Out',
      cancelLabel: 'Cancel',
    );
    if (!ok) return;
    // The PIN guards this device for this person - it must not outlive their session.
    await ref.read(appLockProvider.notifier).clear();
    await ref.read(sessionControllerProvider.notifier).logout();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _requestDeletion(BuildContext context, WidgetRef ref) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Request account deletion?',
      message: "Your student account sits under your academy's records, so deletion has to be approved by your "
          "academy admin. We'll send them a request on your behalf.",
      confirmLabel: 'Send Request',
      cancelLabel: 'Cancel',
    );
    if (!ok) return;
    try {
      final created = await ref.read(authApiProvider).requestAccountDeletion();
      if (context.mounted) {
        AppNotice.success(
            context, created ? 'Deletion request sent to your academy admin' : 'You already have a request pending');
      }
    } catch (e) {
      if (context.mounted) AppNotice.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(localeProvider);
    final user = ref.watch(sessionControllerProvider).user;
    // Students can also change their login email (verified by a code sent to the new address).
    final isStudent = user?.activeMembership?.roleType == 'STUDENT';
    final lock = ref.watch(appLockProvider);
    final photo = ref.watch(selfProfileProvider).valueOrNull?.profileImageUrl ?? user?.profileImageUrl;

    return SettingsPage(
      title: 'Settings',
      children: [
        // ---- Identity ----
        SettingsCard(
          child: Row(children: [
            PhotoAvatar(name: user?.fullName ?? '', url: photo, size: 44),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.fullName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.bold, color: palette.text)),
                const SizedBox(height: 1),
                Text('@${user?.username ?? ''}', style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
              ]),
            ),
          ]),
        ),

        // ---- Preferences ----
        const SettingsSectionLabel('Preferences'),
        SettingsCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SettingsIconTile(icon: Icons.wb_sunny_outlined, color: palette.gold, soft: palette.goldSoft),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Theme', style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                      Text('Choose how Owleo N.E.S.T. looks on this device',
                          style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                SettingsThemeTabs(
                  selected: themeMode,
                  lightFirst: true,
                  onChanged: (m) => ref.read(themeModeProvider.notifier).setThemeMode(m),
                ),
              ]),
            ),
            Divider(height: 1, color: palette.borderSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 13, 4, 0),
              child: Row(children: [
                SettingsIconTile(icon: Icons.language, color: palette.gateway, soft: palette.gatewaySoft),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('App Language', style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text('Used across Owleo N.E.S.T. on this device',
                          style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                    ),
                  ]),
                ),
                const SizedBox(width: AppSpacing.md),
                SettingsLanguageDropdown(
                  selected: language,
                  onSelected: (option) async {
                    if (option == language) return;
                    await ref.read(localeProvider.notifier).setLanguage(option);
                    if (context.mounted) {
                      // Read the string AFTER the switch so the confirmation itself appears in the
                      // language just chosen.
                      AppNotice.success(context, AppLocalizations.of(context).languageChanged);
                    }
                  },
                ),
              ]),
            ),
          ]),
        ),

        // ---- Account & Security ----
        const SettingsSectionLabel('Account & Security'),
        SettingsRowGroup(rows: [
          if (isStudent)
            SettingsNavRow(
              icon: Icons.mail_outline,
              color: palette.primary,
              soft: palette.primarySoft,
              title: 'Login Email',
              subtitle: (user?.email ?? '').isEmpty ? 'Add your login email' : user!.email!,
              onTap: () => _open(context, const ChangeEmailScreen()),
            ),
          SettingsNavRow(
            icon: Icons.lock_outline,
            color: palette.primary,
            soft: palette.primarySoft,
            title: 'Password',
            subtitle: 'Change your account password',
            onTap: () => _open(context, const ChangePasswordScreen()),
          ),
          SettingsSwitchRow(
            icon: Icons.vpn_key_outlined,
            color: palette.violet,
            soft: palette.violetSoft,
            title: 'App Lock',
            subtitle: lock.hasPin ? 'Unlock with a 4-digit PIN' : 'Off',
            value: lock.hasPin,
            onChanged: (on) async {
              if (on) {
                await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
              } else {
                final ok = await showAppConfirmDialog(
                  context: context,
                  title: 'Turn off App Lock?',
                  message: "You won't need a PIN to open Owleo N.E.S.T. on this device anymore.",
                  confirmLabel: 'Turn Off',
                  cancelLabel: 'Cancel',
                );
                if (ok) await ref.read(appLockProvider.notifier).clear();
              }
            },
          ),
          if (lock.hasPin)
            SettingsNavRow(
              icon: Icons.edit_outlined,
              color: palette.violet,
              soft: palette.violetSoft,
              title: 'Change PIN',
              subtitle: null,
              onTap: () => _open(context, const PinSetupScreen()),
            ),
        ]),

        // ---- Notifications ----
        const SettingsSectionLabel('Notifications'),
        const NotificationPrefsCard(),

        // ---- Support ----
        const SettingsSectionLabel('Support'),
        SettingsRowGroup(rows: [
          SettingsNavRow(
            icon: Icons.help_outline,
            color: palette.gateway,
            soft: palette.gatewaySoft,
            title: 'Help & Support',
            subtitle: 'FAQs and contacting our team',
            onTap: () => _open(context, const _HelpScreen()),
          ),
          if (isStudent)
            SettingsNavRow(
              icon: Icons.phone_outlined,
              color: palette.primary,
              soft: palette.primarySoft,
              title: 'Contact Us',
              subtitle: 'Reach your academy directly',
              onTap: () => _open(context, const ContactUsScreen()),
            ),
          SettingsNavRow(
            icon: Icons.info_outline,
            color: palette.gold,
            soft: palette.goldSoft,
            title: 'About Owleo',
            subtitle: 'Version, legal & platform info',
            onTap: () => _open(context, const AboutOwleoScreen()),
          ),
        ]),

        // ---- Account ----
        const SettingsSectionLabel('Account'),
        _WideButton(
          icon: Icons.logout,
          label: 'Log Out',
          onTap: () => _logout(context, ref),
        ),
        if (isStudent) ...[
          const SizedBox(height: 10),
          _WideButton(
            icon: Icons.delete_outline,
            label: 'Request Account Deletion',
            danger: true,
            onTap: () => _requestDeletion(context, ref),
          ),
        ],
      ],
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: danger ? palette.notPaidSoft : Colors.transparent,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: danger ? palette.notPaid.withValues(alpha: 0.33) : palette.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: danger ? palette.notPaid : palette.text),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: AppType.xl, fontWeight: AppType.semi, color: danger ? palette.notPaid : palette.text)),
        ]),
      ),
    );
  }
}

const _faqs = [
  (
    'How do I check my attendance?',
    'Open the Attendance tab from the bottom navigation to see your day-wise record for the current month, '
        'along with your overall percentage.',
  ),
  (
    'How do I pay my fees?',
    "Go to the Fees tab to view what's due and pay online. Receipts are generated automatically once a payment goes "
        'through.',
  ),
  (
    'Can I switch between academies?',
    "Yes — if you're enrolled at more than one academy, use the academy switcher at the top of your dashboard.",
  ),
  (
    'Who do I contact if my details are wrong?',
    "Reach out to your academy's admin — they manage enrolment details like your batch, courses and guardian "
        'information.',
  ),
];

class _HelpScreen extends StatefulWidget {
  const _HelpScreen();

  @override
  State<_HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<_HelpScreen> {
  int _open = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SettingsPage(
      title: 'Help & Support',
      children: [
        const SettingsSectionLabel('Frequently Asked'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Column(children: [
            for (var i = 0; i < _faqs.length; i++)
              Container(
                decoration: BoxDecoration(
                    border: i == _faqs.length - 1 ? null : Border(bottom: BorderSide(color: palette.borderSoft))),
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Pressable(
                    onTap: () => setState(() => _open = _open == i ? -1 : i),
                    child: Row(children: [
                      Expanded(
                        child: Text(_faqs[i].$1,
                            style: TextStyle(fontSize: 13.5, fontWeight: AppType.semi, color: palette.text)),
                      ),
                      Icon(_open == i ? Icons.chevron_right : Icons.expand_more, size: 15, color: palette.textFaint),
                    ]),
                  ),
                  if (_open == i)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_faqs[i].$2, style: TextStyle(fontSize: 12.5, height: 1.55, color: palette.textMuted)),
                    ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: AppSpacing.x4l),
        SettingsCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Still need help?', style: TextStyle(fontSize: 13.5, fontWeight: AppType.bold, color: palette.text)),
                const SizedBox(height: 2),
                Text('Reach your academy directly', style: TextStyle(fontSize: 11.5, color: palette.textMuted)),
              ]),
            ),
            const SizedBox(width: 12),
            Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactUsScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: palette.primary, borderRadius: AppRadii.all(11)),
                child: Text('Contact Us',
                    style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.onPrimary)),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/i18n/app_languages.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_billing_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_export_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart' show academyProfileProvider;
import 'package:nest_fe/features/academy/presentation/academy_requests_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';
import 'package:nest_fe/features/academy/presentation/academy_support_screens.dart';
import 'package:nest_fe/features/academy/presentation/change_password_screen.dart';
import 'package:nest_fe/features/academy/presentation/ownership_transfer_screen.dart';
import 'package:nest_fe/features/profile/presentation/settings_sections.dart' show ChangeEmailScreen;

/// The Academy Admin's settings home, laid out like the reference design.
///
/// Everything on it is backed by something real: the theme and the academy's default language are
/// saved, the login email and password are the admin's own account, billing shows the real plan,
/// usage and invoices, exports download real CSVs, and the things only the Owleo team can do
/// (ownership transfer, closing the academy, changing plan) are requests the team answers.
class AcademySettingsScreen extends ConsumerWidget {
  const AcademySettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _setLanguage(BuildContext context, WidgetRef ref, AcademySettings settings, AppLanguage picked) async {
    if (picked.languageCode == settings.defaultLanguage) return;
    try {
      await ref.read(academySettingsApiProvider).updateLanguage(picked.languageCode);
      ref.invalidate(academySettingsProvider);
      if (context.mounted) AppNotice.success(context, 'Default language set to ${picked.englishName}.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _requestClosure(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Request academy closure?',
      message: 'Closing an academy permanently ends its subscription and access for everyone linked to it. '
          "This can only be carried out by Owleo's Super Admin team after review.",
      confirmLabel: 'Submit Request',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(academySettingsApiProvider).submitRequest(kind: AcademyRequestKind.academyClosure);
      ref.invalidate(myAcademyRequestsProvider);
      if (context.mounted) AppNotice.success(context, 'Closure request submitted to Owleo Super Admin.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(sessionControllerProvider).user;
    final membership = user?.activeMembership;

    if (user == null || membership == null || !user.isActiveAcademyAdmin) {
      return const Scaffold(body: Center(child: Text('Academy Admin access required.')));
    }

    final academyId = membership.academyId;
    final profileAsync = ref.watch(academyProfileProvider);
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final subscription = ref.watch(subscriptionProvider).valueOrNull;
    final exports = ref.watch(recentExportsProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);

    final language = AppLanguage.fromTag(settings?.defaultLanguage);
    final ownerName = (settings?.ownerName ?? '').trim().isNotEmpty ? settings!.ownerName! : user.fullName;
    final plan = subscription?.current;
    final planLine = plan == null
        ? 'Current plan and invoices'
        : '${plan.displayName}${plan.monthlyPrice == null ? '' : ' · ${money(plan.monthlyPrice!)}/month'}';

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            const AppTopBar(title: 'Academy Settings'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(academyProfileProvider);
                  ref.invalidate(academySettingsProvider);
                  ref.invalidate(subscriptionProvider);
                  ref.invalidate(recentExportsProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxl, AppSpacing.page, AppSpacing.x6l),
                  children: [
                    // ---- Identity ----
                    AsyncValueView<AcademyProfile>(
                      value: profileAsync,
                      onRetry: () => ref.invalidate(academyProfileProvider),
                      data: (context, profile) => SettingsCard(
                        child: Row(
                          children: [
                            SettingsIconTile(
                              icon: Icons.account_balance_outlined,
                              color: palette.primary,
                              soft: palette.primarySoft,
                              size: 44,
                              image: profile.logoUrl,
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.bold, color: palette.text)),
                                  const SizedBox(height: 1),
                                  Text('Owner: $ownerName', style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x4l),
                    const SettingsNote(
                      text: 'This academy is its own account, independent of any one person. '
                          'It stays intact even if the owner or a trainer leaves.',
                    ),

                    // ---- Preferences ----
                    const SettingsSectionLabel('Preferences'),
                    SettingsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SettingsIconTile(icon: Icons.wb_sunny_outlined, color: palette.gold, soft: palette.goldSoft),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Theme',
                                              style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                                          Text('Choose how Owleo N.E.S.T. looks',
                                              style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _ThemeTabs(selected: themeMode, onChanged: (m) => ref.read(themeModeProvider.notifier).setThemeMode(m)),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: palette.borderSoft),
                          _PlainRow(
                            icon: Icons.language,
                            color: palette.gateway,
                            soft: palette.gatewaySoft,
                            title: 'Default Language',
                            subtitle: 'Used for receipts, reminders & broadcasts to students',
                            trailing: settings == null
                                ? null
                                : _LanguageDropdown(
                                    selected: language,
                                    onSelected: (l) => _setLanguage(context, ref, settings, l),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // ---- Academy Login ----
                    const SettingsSectionLabel('Academy Login'),
                    SettingsCard(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                      child: Column(
                        children: [
                          Pressable(
                            onTap: () => _open(context, const ChangeEmailScreen()),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      SettingsIconTile(icon: Icons.mail_outline, color: palette.primary, soft: palette.primarySoft),
                                      const SizedBox(width: AppSpacing.lg),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Login Email',
                                                style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                                            Text("Used to sign in to your account",
                                                style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, size: 16, color: palette.textFaint),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(left: 46),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: palette.surfaceHigh,
                                      borderRadius: AppRadii.all(AppRadii.lg),
                                      border: Border.all(color: palette.border),
                                    ),
                                    child: Text(
                                      (user.email ?? '').isEmpty ? 'Add your login email' : user.email!,
                                      style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(height: 1, color: palette.borderSoft),
                          SettingsNavRow(
                            icon: Icons.lock_outline,
                            color: palette.primary,
                            soft: palette.primarySoft,
                            title: 'Login Password',
                            subtitle: 'Used to sign in to your account',
                            onTap: () => _open(context, const ChangePasswordScreen()),
                          ),
                        ],
                      ),
                    ),

                    // ---- Ownership ----
                    const SettingsSectionLabel('Ownership'),
                    SettingsCard(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              children: [
                                PersonAvatar(name: ownerName, seed: academyId, size: 44),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(ownerName,
                                          style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                                      Text('Academy owner', style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: palette.goldSoft,
                                    borderRadius: AppRadii.all(AppRadii.pill),
                                    border: Border.all(color: palette.gold.withValues(alpha: 0.27)),
                                  ),
                                  child: Icon(Icons.workspace_premium_outlined, size: 12, color: palette.gold),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: palette.borderSoft),
                          SettingsNavRow(
                            icon: Icons.swap_horiz,
                            color: palette.gold,
                            soft: palette.goldSoft,
                            title: 'Request Ownership Transfer',
                            subtitle: 'Handled by Owleo Super Admin',
                            onTap: () => _open(context, const OwnershipTransferScreen()),
                          ),
                        ],
                      ),
                    ),

                    // ---- Billing ----
                    const SettingsSectionLabel('Billing'),
                    SettingsRowGroup(rows: [
                      SettingsNavRow(
                        icon: Icons.credit_card_outlined,
                        color: palette.gold,
                        soft: palette.goldSoft,
                        title: 'Subscription Plan',
                        subtitle: planLine,
                        onTap: () => _open(context, AcademyBillingScreen(academyId: academyId)),
                      ),
                    ]),

                    // ---- Data ----
                    const SettingsSectionLabel('Data'),
                    SettingsRowGroup(rows: [
                      SettingsNavRow(
                        icon: Icons.storage_outlined,
                        color: palette.violet,
                        soft: palette.violetSoft,
                        title: 'Export & Backup',
                        subtitle: (exports == null || exports.isEmpty)
                            ? 'Download your academy\'s data as CSV'
                            : 'Last export: ${shortDate(exports.first.createdAt)}',
                        onTap: () => _open(context, const AcademyExportScreen()),
                      ),
                    ]),

                    // ---- Support ----
                    const SettingsSectionLabel('Support'),
                    SettingsRowGroup(rows: [
                      SettingsNavRow(
                        icon: Icons.help_outline,
                        color: palette.gateway,
                        soft: palette.gatewaySoft,
                        title: 'Help & Support',
                        subtitle: 'FAQs and contacting our team',
                        onTap: () => _open(context, const HelpSupportScreen()),
                      ),
                      SettingsNavRow(
                        icon: Icons.phone_outlined,
                        color: palette.primary,
                        soft: palette.primarySoft,
                        title: 'Contact Us',
                        subtitle: 'Reach the Owleo team directly',
                        onTap: () => _open(context, const ContactSupportScreen()),
                      ),
                      SettingsNavRow(
                        icon: Icons.inbox_outlined,
                        color: palette.coral,
                        soft: palette.coralSoft,
                        title: 'My Requests',
                        subtitle: 'Track what you have asked the team for',
                        onTap: () => _open(context, const AcademyRequestsScreen()),
                      ),
                      SettingsNavRow(
                        icon: Icons.info_outline,
                        color: palette.gold,
                        soft: palette.goldSoft,
                        title: 'About Owleo',
                        subtitle: 'Version & platform info',
                        onTap: () => _open(context, const AboutOwleoScreen()),
                      ),
                    ]),

                    // ---- Danger zone ----
                    const SettingsSectionLabel('Danger Zone'),
                    Pressable(
                      onTap: () => _requestClosure(context, ref),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.notPaidSoft,
                          borderRadius: AppRadii.all(AppRadii.xl),
                          border: Border.all(color: palette.notPaid.withValues(alpha: 0.33)),
                        ),
                        child: Text('Request Academy Closure',
                            style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.notPaid)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// System / Light / Dark: a flat raised track, the selected option filled gold, each with its icon.
class _ThemeTabs extends StatelessWidget {
  const _ThemeTabs({required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const options = [
      (ThemeMode.system, 'System', Icons.monitor_outlined),
      (ThemeMode.light, 'Light', Icons.wb_sunny_outlined),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: palette.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Pressable(
                onTap: () => onChanged(options[i].$1),
                child: AnimatedContainer(
                  duration: AppMotion.fade,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: options[i].$1 == selected ? palette.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(options[i].$3, size: 13, color: options[i].$1 == selected ? palette.onGold : palette.textMuted),
                      const SizedBox(width: 6),
                      Text(options[i].$2,
                          style: TextStyle(
                              fontSize: AppType.base,
                              fontWeight: options[i].$1 == selected ? AppType.heavy : AppType.semi,
                              color: options[i].$1 == selected ? palette.onGold : palette.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A non-tappable settings row with a widget on the right (the language dropdown).
class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.icon, required this.color, required this.soft, required this.title, required this.subtitle, this.trailing});

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 13, 4, 0),
      child: Row(
        children: [
          SettingsIconTile(icon: icon, color: color, soft: soft),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.semi, color: palette.text)),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(subtitle, style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpacing.md), trailing!],
        ],
      ),
    );
  }
}

/// "English ⌄" chip that opens a panel of languages under it, the selected one ticked.
class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({required this.selected, required this.onSelected});

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<AppLanguage>(
      onSelected: onSelected,
      color: palette.surfaceHigh,
      elevation: 8,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 38),
      constraints: const BoxConstraints(minWidth: 190),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.xl), side: BorderSide(color: palette.border)),
      itemBuilder: (context) => [
        for (final l in AppLanguage.values)
          PopupMenuItem<AppLanguage>(
            value: l,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(l.nativeName, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.semi, color: palette.text)),
                ),
                if (l == selected) Icon(Icons.check, size: 13, color: palette.primary),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.nativeName, style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}

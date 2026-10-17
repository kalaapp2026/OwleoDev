import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/segmented_control.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_billing_api.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/presentation/academy_billing_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart' show academyProfileProvider;
import 'package:nest_fe/features/academy/presentation/change_password_screen.dart';
import 'package:nest_fe/features/profile/presentation/user_settings_screen.dart';

/// The Academy Admin's own settings home. Deliberately smaller than the reference design: this
/// app has no academy-owned login, ownership-transfer workflow, data export, or support inbox to
/// wire up, so those cards are left out entirely rather than shown with nothing behind them. What
/// ships is real: the academy's own identity/plan, the theme, the admin's own account password,
/// and their academy's real invoice history.
class AcademySettingsScreen extends ConsumerWidget {
  const AcademySettingsScreen({super.key});

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
    final detailAsync = ref.watch(academyDetailProvider(academyId));
    final themeMode = ref.watch(themeModeProvider);

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
                  ref.invalidate(academyDetailProvider(academyId));
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.x6l),
                  children: [
                    AsyncValueView<AcademyProfile>(
                      value: profileAsync,
                      onRetry: () => ref.invalidate(academyProfileProvider),
                      data: (context, profile) => _Card(
                        child: Row(
                          children: [
                            _IconTile(
                              icon: Icons.account_balance_outlined,
                              color: palette.primary,
                              soft: palette.primarySoft,
                              size: 44,
                              image: profile.logoUrl,
                            ),
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.name,
                                      style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.heavy, color: palette.text)),
                                  const SizedBox(height: 2),
                                  detailAsync.maybeWhen(
                                    data: (a) => Text(a.plan != null ? '${a.plan} plan' : 'No plan set',
                                        style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                                    orElse: () => const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const _SectionLabel('Preferences'),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _IconTile(icon: Icons.wb_sunny_outlined, color: palette.gold, soft: palette.goldSoft),
                              const SizedBox(width: AppSpacing.xl),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Theme',
                                        style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.heavy, color: palette.text)),
                                    Text('Choose how Owleo N.E.S.T. looks',
                                        style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AppSegmentedControl<ThemeMode>(
                            options: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                            labelOf: (m) => switch (m) {
                              ThemeMode.system => 'System',
                              ThemeMode.light => 'Light',
                              ThemeMode.dark => 'Dark',
                            },
                            isSelected: (m) => m == themeMode,
                            onTap: (m) => ref.read(themeModeProvider.notifier).setThemeMode(m),
                            activeColorOf: (_, _) => palette.gold,
                            activeTextColorOf: (_, _) => palette.onGold,
                          ),
                        ],
                      ),
                    ),
                    const _SectionLabel('Account'),
                    _Card(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _NavRow(
                            icon: Icons.lock_outline,
                            color: palette.primary,
                            soft: palette.primarySoft,
                            title: 'Login Password',
                            subtitle: 'Change your own account password',
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
                          ),
                          Divider(height: 1, color: palette.borderSoft),
                          _NavRow(
                            icon: Icons.credit_card_outlined,
                            color: palette.gateway,
                            soft: palette.gatewaySoft,
                            title: 'Billing & Subscription',
                            subtitle: 'Current plan and invoice history',
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => AcademyBillingScreen(academyId: academyId))),
                          ),
                          Divider(height: 1, color: palette.borderSoft),
                          _NavRow(
                            icon: Icons.language,
                            color: palette.violet,
                            soft: palette.violetSoft,
                            title: 'Language & display',
                            subtitle: 'Display language and more',
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const UserSettingsScreen())),
                          ),
                        ],
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

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(AppSpacing.xxl)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.x4l, 0, AppSpacing.lg),
      child: Text(text.toUpperCase(), style: AppType.sectionLabel(context.palette.textMuted)),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color, required this.soft, this.size = 36, this.image});

  final IconData icon;
  final Color color;
  final Color soft;
  final double size;
  final String? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: soft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: image != null
          ? Image.network(image!, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(icon, size: size * 0.5, color: color))
          : Icon(icon, size: size * 0.5, color: color),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Row(
          children: [
            _IconTile(icon: icon, color: color, soft: soft),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.heavy, color: palette.text)),
                  Text(subtitle, style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/account_store.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/pressable.dart';

/// The saved accounts on this device, newest login last. Read fresh each time the sheet opens.
final _savedAccountsProvider = FutureProvider.autoDispose<List<SavedAccount>>((ref) => AccountStore.instance.all());

/// Username row at the top of Profile - tapping it opens the account switcher, like Instagram.
class AccountSwitcherBar extends ConsumerWidget {
  const AccountSwitcherBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const SizedBox.shrink();
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Pressable(
          onTap: () => showAccountSwitcherSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: palette.borderSoft),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PersonAvatar(name: user.fullName, seed: user.id, size: 24),
                const SizedBox(width: AppSpacing.md),
                Text(
                  user.username,
                  style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The prototype's top-right dropdown: the current profile (tap to open it), the other accounts on
/// this device to switch to, and Add account. Anchored under the header, growing from its right edge.
Future<void> showAccountMenu(BuildContext context, {required VoidCallback onOpenProfile}) {
  final top = MediaQuery.paddingOf(context).top + kToolbarHeight - 4;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close account menu',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), alignment: Alignment.topRight, child: child),
      );
    },
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(top: top, right: AppSpacing.page),
        child: _AccountMenuPanel(onOpenProfile: onOpenProfile),
      ),
    ),
  );
}

class _AccountMenuPanel extends ConsumerWidget {
  const _AccountMenuPanel({required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(sessionControllerProvider).user;
    final accounts = ref.watch(_savedAccountsProvider).valueOrNull ?? const <SavedAccount>[];
    if (user == null) return const SizedBox.shrink();
    final others = accounts.where((a) => a.userId != user.id).toList();
    final membership = user.activeMembership;
    final subtitle = [
      user.role.replaceAll('_', ' '),
      if (membership?.academyName != null) membership!.academyName!,
    ].join(' · ');

    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xs),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: AppType.heavy, letterSpacing: 0.4, color: palette.textFaint),
          ),
        );

    return Material(
      color: palette.surface,
      elevation: 12,
      shadowColor: Colors.black45,
      borderRadius: AppRadii.all(AppRadii.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 280, maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Pressable(
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenProfile();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Row(
                      children: [
                        PersonAvatar(name: user.fullName, seed: user.id, size: 36),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: AppType.md, fontWeight: AppType.heavy, color: palette.text)),
                              Text(subtitle,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: palette.textFaint),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: palette.borderSoft),
                label(others.isEmpty ? 'Accounts' : 'Switch account'),
                for (final a in others)
                  Pressable(
                    onTap: () {
                      Navigator.of(context).pop();
                      ref.read(sessionControllerProvider.notifier).switchAccount(a.userId);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                      child: Row(
                        children: [
                          PersonAvatar(name: a.fullName, seed: a.userId, size: 28),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.fullName.isEmpty ? a.username : a.fullName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
                                Text('@${a.username}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: AppType.sm, color: palette.textFaint)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Pressable(
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/add-account');
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.primarySoft,
                            border: Border.all(color: palette.primary, width: 1.5),
                          ),
                          child: Icon(Icons.add_rounded, size: 16, color: palette.primary),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Text('Add account',
                            style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAccountSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AccountSwitcherSheet(),
  );
}

class _AccountSwitcherSheet extends ConsumerWidget {
  const _AccountSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final activeId = ref.watch(sessionControllerProvider).user?.id;
    final accounts = ref.watch(_savedAccountsProvider).valueOrNull ?? const <SavedAccount>[];

    return Container(
      decoration: BoxDecoration(color: palette.surface, borderRadius: AppRadii.sheetTop),
      padding: const EdgeInsets.fromLTRB(AppSpacing.x5l, AppSpacing.xl, AppSpacing.x5l, AppSpacing.x6l),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.x4l),
                decoration: BoxDecoration(color: palette.border, borderRadius: AppRadii.all(AppRadii.pill)),
              ),
            ),
            Text(
              'Switch account',
              style: TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.text),
            ),
            const SizedBox(height: AppSpacing.lg),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in accounts)
                    _AccountRow(
                      account: a,
                      active: a.userId == activeId,
                      onTap: () {
                        Navigator.of(context).pop();
                        ref.read(sessionControllerProvider.notifier).switchAccount(a.userId);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Pressable(
              onTap: () {
                Navigator.of(context).pop();
                context.push('/add-account');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.primarySoft,
                        border: Border.all(color: palette.primary, width: 1.5),
                      ),
                      child: Icon(Icons.add_rounded, color: palette.primary),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Text(
                      'Add account',
                      style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.primary),
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.active, required this.onTap});

  final SavedAccount account;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            PersonAvatar(name: account.fullName, seed: account.userId, size: 40),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.fullName.isEmpty ? account.username : account.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text),
                  ),
                  Text(
                    '@${account.username}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppType.sm, color: palette.textMuted),
                  ),
                ],
              ),
            ),
            Icon(
              active ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: active ? palette.primary : palette.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

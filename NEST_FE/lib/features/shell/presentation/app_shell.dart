import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_colors.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/widgets/owleo_wordmark.dart';
import 'package:nest_fe/features/dashboard/presentation/dashboard_screen.dart';
import 'package:nest_fe/features/enrolment/presentation/batches_screen.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart';
import 'package:nest_fe/features/profile/presentation/profile_screen.dart';
import 'package:nest_fe/features/shell/presentation/more_menu_sheet.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';
import 'package:nest_fe/features/social/presentation/notifications_tab.dart';

enum AppMode { social, erp }

/// PRD 3.1: one bottom nav bar whose centre slot (the Owleo/NEST logo) morphs the other four
/// slots between the Social set and the ERP set, on the same session - roles with no ERP access
/// (Artist/Guest) never see the morph at all. Each side keeps its own tab state independently
/// (IndexedStack, not rebuilt on toggle) so switching back lands exactly where you left off.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => AppShellState();
}

/// Public so distant descendants (Dashboard's quick-action tiles, the More sheet) can reach in
/// via `context.findAncestorStateOfType<AppShellState>()` and switch tabs in place, instead of
/// pushing a second AppShell onto the nav stack - see goToErpTab.
class AppShellState extends ConsumerState<AppShell> {
  AppMode _mode = AppMode.social;
  int _socialIndex = 0;
  int _erpIndex = 0;

  static const _socialTitles = ['Feed', 'Events', '', 'Notifications', 'Profile'];
  static const _erpTitles = ['Dashboard', 'Batches', '', 'Fees', 'Profile'];

  void goToErpTab(int index) => setState(() {
        _mode = AppMode.erp;
        _erpIndex = index;
      });

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final hasErpAccess = user?.hasErpAccess ?? false;

    final title = _mode == AppMode.social ? _socialTitles[_socialIndex] : _erpTitles[_erpIndex];

    return Scaffold(
      appBar: AppBar(
        title: title.isEmpty ? const OwleoWordmark() : Text(title),
        actions: [
          if (_mode == AppMode.erp) ...[
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Profile',
              onPressed: () => setState(() => _erpIndex = 4),
            ),
            if (user != null && user.memberships.length > 1)
              PopupMenuButton<String>(
                tooltip: 'Switch academy',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (membershipId) =>
                    ref.read(sessionControllerProvider.notifier).switchActiveMembership(membershipId),
                itemBuilder: (context) => user.memberships
                    .map(
                      (m) => PopupMenuItem<String>(
                        value: m.membershipId,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(m.academyName ?? m.academyId),
                                  Text(
                                    m.roleType.replaceAll('_', ' '),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (m.membershipId == user.activeMembershipId)
                              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 18),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ],
      ),
      body: IndexedStack(
        index: _mode == AppMode.social ? 0 : 1,
        children: [
          IndexedStack(
            index: _socialIndex,
            children: const [FeedScreen(), EventsTab(), SizedBox.shrink(), NotificationsTab(), ProfileScreen()],
          ),
          IndexedStack(
            index: _erpIndex,
            children: [
              const DashboardScreen(),
              const BatchesScreen(),
              const SizedBox.shrink(),
              const FeesScreen(),
              const ProfileScreen(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        mode: _mode,
        socialIndex: _socialIndex,
        erpIndex: _erpIndex,
        canToggleErp: hasErpAccess,
        onSocialTap: (i) => setState(() => _socialIndex = i),
        onErpTap: (i) => setState(() => _erpIndex = i),
        onMoreTap: () => showMoreMenu(context, ref),
        onToggle: () {
          if (!hasErpAccess) return;
          setState(() => _mode = _mode == AppMode.social ? AppMode.erp : AppMode.social);
        },
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.mode,
    required this.socialIndex,
    required this.erpIndex,
    required this.canToggleErp,
    required this.onSocialTap,
    required this.onErpTap,
    required this.onMoreTap,
    required this.onToggle,
  });

  final AppMode mode;
  final int socialIndex;
  final int erpIndex;
  final bool canToggleErp;
  final ValueChanged<int> onSocialTap;
  final ValueChanged<int> onErpTap;
  final VoidCallback onMoreTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSocial = mode == AppMode.social;
    final currentIndex = isSocial ? socialIndex : erpIndex;

    final leftIcons = isSocial
        ? const [(Icons.dynamic_feed_outlined, 'Feed'), (Icons.celebration_outlined, 'Events')]
        : const [(Icons.dashboard_outlined, 'Dashboard'), (Icons.groups_outlined, 'Batches')];
    final rightIcons = isSocial
        ? const [(Icons.notifications_outlined, 'Alerts'), (Icons.person_outline, 'Profile')]
        : const [(Icons.account_balance_wallet_outlined, 'Fees'), (Icons.apps_rounded, 'More')];

    Widget navItem(IconData icon, String label, int index, ValueChanged<int> onTap) {
      final selected = currentIndex == index;
      final color = selected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.45);
      return Expanded(
        child: InkWell(
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 23),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: color, fontSize: 10.5)),
              ],
            ),
          ),
        ),
      );
    }

    // Unlike the other four slots, "More" opens a bottom sheet rather than switching to a tab -
    // it never has a "selected" state of its own, so it always renders in the neutral colour.
    Widget moreItem(IconData icon, String label, VoidCallback onTap) {
      final color = colorScheme.onSurface.withValues(alpha: 0.45);
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 23),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: color, fontSize: 10.5)),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            navItem(leftIcons[0].$1, leftIcons[0].$2, 0, isSocial ? onSocialTap : onErpTap),
            navItem(leftIcons[1].$1, leftIcons[1].$2, 1, isSocial ? onSocialTap : onErpTap),
            Expanded(
              child: Opacity(
                opacity: canToggleErp ? 1 : 0.35,
                child: InkWell(
                  onTap: onToggle,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: _NavLogoToggle(),
                  ),
                ),
              ),
            ),
            navItem(rightIcons[0].$1, rightIcons[0].$2, 3, isSocial ? onSocialTap : onErpTap),
            if (isSocial)
              navItem(rightIcons[1].$1, rightIcons[1].$2, 4, onSocialTap)
            else
              moreItem(rightIcons[1].$1, rightIcons[1].$2, onMoreTap),
          ],
        ),
      ),
    );
  }
}

class _NavLogoToggle extends StatelessWidget {
  const _NavLogoToggle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightIconBg,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.primary, width: 1.6),
      ),
      child: Center(
        child: Text(
          'O',
          style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/theme_controller.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:nest_fe/core/widgets/owleo_wordmark.dart';
import 'package:nest_fe/features/attendance/presentation/attendance_home_screen.dart';
import 'package:nest_fe/features/dashboard/presentation/dashboard_screen.dart';
import 'package:nest_fe/features/fees/presentation/fees_landing_screen.dart';
import 'package:nest_fe/features/notification/data/notification_api.dart';
import 'package:nest_fe/features/notification/presentation/notifications_screen.dart';
import 'package:nest_fe/features/platform/data/platform_settings_api.dart';
import 'package:nest_fe/features/platform/presentation/academy_stats_screen.dart';
import 'package:nest_fe/features/platform/presentation/platform_settings_screen.dart';
import 'package:nest_fe/features/platform/presentation/billing_screen.dart';
import 'package:nest_fe/features/platform/presentation/super_admin_dashboard_screen.dart';
import 'package:nest_fe/features/profile/presentation/profile_screen.dart';
import 'package:nest_fe/features/shell/presentation/more_menu_sheet.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';
import 'package:nest_fe/features/social/presentation/my_posts_screen.dart';
import 'package:nest_fe/features/social/presentation/search_profiles_screen.dart';

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

  /// Whether the user has moved the toggle themselves. Until they do, the shell follows the
  /// Super Admin's configured starting side; after they do, it stops overriding them - otherwise
  /// the app would keep yanking them back on every rebuild.
  bool _modeChosenByUser = false;

  // Built per frame from AppLocalizations rather than const lists - a const list can't change
  // when the user switches language.
  List<String> _socialTitles(AppLocalizations t) =>
      [t.navFeed, t.navEvents, '', t.navMyPosts, t.navProfile];
  List<String> _erpTitles(AppLocalizations t) =>
      [t.navDashboard, 'Attendance', '', t.navFees, t.navProfile];

  /// A Super Admin belongs to no academy, so Batches and Fees - which are scoped to the active
  /// academy - have nothing to show them. Their ERP side is the platform console instead.
  List<String> _superAdminErpTitles(AppLocalizations t) =>
      [t.navPlatform, t.navAcademies, '', t.navBilling, t.navProfile];

  void goToErpTab(int index) => setState(() {
        _mode = AppMode.erp;
        _erpIndex = index;
      });

  /// A second copy of the same bottom nav bar, for the More sheet to paint on top of its own
  /// blurred backdrop. A modal route's Overlay always paints above the Scaffold's
  /// bottomNavigationBar - reserving empty space in the sheet and hoping the real one shows
  /// through underneath was tried and is not reliable, so the sheet renders this instead: visually
  /// identical, but guaranteed sharp and tappable regardless of what the modal route is doing.
  /// [onNavigate] runs before any tap actually changes tab/mode, so the caller showing this copy
  /// can close itself first. [onMoreTap] defaults to [onNavigate] too - right for the More sheet's
  /// own copy, where tapping More again just closes it - but a pushed "More"-destination screen
  /// (see app_router.dart's _WithNavBar) needs its own override: reusing [onNavigate] there just
  /// pops back to whatever tab AppShell was last on instead of actually opening the menu, which is
  /// the exact bug this parameter exists to let that caller avoid.
  Widget buildOverlayBottomNav({required VoidCallback onNavigate, VoidCallback? onMoreTap}) {
    final user = ref.watch(sessionControllerProvider).user;
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final settings = ref.watch(platformSettingsProvider).valueOrNull ?? PlatformSettings.fallback;
    final erpAvailable = settings.allowsErp && (user?.hasErpAccess ?? false);
    final socialAvailable = settings.allowsSocial || !erpAvailable;
    final canToggle = erpAvailable && socialAvailable;

    return BottomNavBar(
      mode: _mode,
      socialIndex: _socialIndex,
      erpIndex: _erpIndex,
      canToggleErp: canToggle,
      isSuperAdmin: isSuperAdmin,
      onSocialTap: (i) {
        onNavigate();
        setState(() => _socialIndex = i);
      },
      onErpTap: (i) {
        onNavigate();
        setState(() => _erpIndex = i);
      },
      // Tapping "More" again while it's already open just closes it, rather than opening a
      // second sheet on top of itself - unless the caller asked for different behaviour.
      onMoreTap: onMoreTap ?? onNavigate,
      onSearchTap: () {
        onNavigate();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchProfilesScreen()));
      },
      onToggle: () {
        if (!canToggle) return;
        onNavigate();
        setState(() {
          _modeChosenByUser = true;
          _mode = _mode == AppMode.social ? AppMode.erp : AppMode.social;
        });
      },
    );
  }

  /// Keeps [_mode] consistent with what the platform setting actually permits.
  ///
  /// Two separate jobs, and the order matters. First, a side that isn't available can never be
  /// the current one - that's enforced on every build, because the setting can change under a
  /// signed-in user. Second, the configured starting side is applied only until the user picks
  /// for themselves; without that guard the shell would drag them back on every rebuild.
  ///
  /// Assigns [_mode] directly rather than calling setState: this runs DURING build, and calling
  /// setState here would throw.
  void _applyConfiguredMode({
    required bool erpAvailable,
    required bool socialAvailable,
    required bool startsOnErp,
  }) {
    if (_mode == AppMode.erp && !erpAvailable) {
      _mode = AppMode.social;
      return;
    }
    if (_mode == AppMode.social && !socialAvailable) {
      _mode = AppMode.erp;
      return;
    }
    if (_modeChosenByUser) return;

    final wanted = startsOnErp && erpAvailable ? AppMode.erp : AppMode.social;
    if ((wanted == AppMode.erp && erpAvailable) || (wanted == AppMode.social && socialAvailable)) {
      _mode = wanted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final hasErpAccess = user?.hasErpAccess ?? false;
    final isSuperAdmin = user?.isSuperAdmin ?? false;

    // Platform-wide rollout setting (Super Admin). Falls back to "both sides, ERP first" while it
    // loads or if the call fails - briefly showing a toggle that then disappears is better than
    // hiding a side the user is entitled to.
    final settings = ref.watch(platformSettingsProvider).valueOrNull ?? PlatformSettings.fallback;

    // A Guest or Artist has no ERP access at all, so ERP_ONLY would leave them staring at a blank
    // app. They keep Social in that case - the setting is about not showing an unfinished Social
    // side to ERP customers, not about locking social-only users out of the product entirely.
    final erpAvailable = settings.allowsErp && hasErpAccess;
    final socialAvailable = settings.allowsSocial || !erpAvailable;
    final canToggle = erpAvailable && socialAvailable;

    _applyConfiguredMode(erpAvailable: erpAvailable, socialAvailable: socialAvailable,
        startsOnErp: settings.startsOnErp);

    final t = AppLocalizations.of(context);
    final erpTitles = isSuperAdmin ? _superAdminErpTitles(t) : _erpTitles(t);
    final title = _mode == AppMode.social ? _socialTitles(t)[_socialIndex] : erpTitles[_erpIndex];

    // The bell is per-module: in ERP it shows ERP notifications, in Social it shows Social ones -
    // so a Trainer on their fees dashboard never sees "someone liked your post" and vice versa.
    final module = _mode == AppMode.erp ? NotificationModule.erp : NotificationModule.social;

    // The Dashboard tab's own gradient hero (StudentWelcomeHeader / AdminWelcomeHeader) starts
    // right below this bar, for every non-super-admin role - Super Admin keeps the plain bar
    // since their Dashboard tab is the cross-tenant platform console, not this per-academy hero.
    // Tinting the bar to the gradient's own start color (rather than making it transparent and
    // extending the body behind it) gives the same "one continuous hero" look the reference has,
    // without pixel-measuring where the gradient ends - that measurement broke the first time it
    // was tried (font-scale and viewport height both shift it). The bar's academy switcher is
    // hidden in that case too: the student header's gold chip already covers switching there, and
    // showing both would be two inconsistent copies of the same control (a multi-academy admin
    // still has the switcher on every other ERP tab).
    final isDashboardHero = _mode == AppMode.erp && _erpIndex == 0 && !isSuperAdmin;

    return Scaffold(
      // Truly transparent rather than colour-matched to the gradient's start: matching a solid
      // colour to a gradient still leaves a seam the moment the gradient's own stops shift, which
      // is exactly what broke the first time this was tried. Extending the body behind the app bar
      // instead means there is no seam to match - the gradient itself paints straight through, and
      // the app bar's icons just float on top of it, same as the reference's cover header.
      extendBodyBehindAppBar: isDashboardHero,
      appBar: AppBar(
        backgroundColor: isDashboardHero ? Colors.transparent : null,
        elevation: isDashboardHero ? 0 : null,
        foregroundColor: isDashboardHero ? Colors.white : null,
        title: isDashboardHero ? null : (title.isEmpty ? const OwleoWordmark() : Text(title)),
        actions: [
          if (isDashboardHero) const _ThemeToggleButton(),
          // Platform settings live in the app bar, not just on the Platform dashboard: a gear icon
          // is where anyone looks for settings first, and on the dashboard it sat below the charts
          // where it was easy to miss entirely.
          if (isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Platform settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlatformSettingsScreen()),
              ),
            ),
          _NotificationBell(module: module),
          // A real avatar on the hero (matching the reference's ringed circle) rather than the
          // plain outline glyph the non-hero app bars use - it's the one spot in the app where the
          // icon sits directly on the caller's own gradient rather than a flat bar.
          if (isDashboardHero && user != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg, left: AppSpacing.xs),
              child: InkWell(
                borderRadius: AppRadii.all(AppRadii.pill),
                onTap: () => setState(() => _erpIndex = 4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
                  ),
                  child: PersonAvatar(name: user.fullName, seed: user.id, size: 30),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: t.navProfile,
              onPressed: () => setState(() {
                if (_mode == AppMode.erp) {
                  _erpIndex = 4;
                } else {
                  _socialIndex = 4;
                }
              }),
            ),
          if (_mode == AppMode.erp && !isDashboardHero) ...[
            if (user != null && user.hasMultipleAcademies)
              PopupMenuButton<String>(
                tooltip: 'Switch academy',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (membershipId) =>
                    ref.read(sessionControllerProvider.notifier).switchActiveMembership(membershipId),
                itemBuilder: (context) => user.activeMemberships
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
            children: const [FeedScreen(), EventsTab(), SizedBox.shrink(), MyPostsScreen(), ProfileScreen()],
          ),
          // A Super Admin belongs to no academy (PRD 2.4), so every academy-scoped ERP screen -
          // the dashboard's "your courses" tiles, Batches, Fees - has nothing to show them and
          // would just error on open. Their ERP side is the cross-tenant platform console instead.
          IndexedStack(
            index: _erpIndex,
            children: isSuperAdmin
                ? const [
                    SuperAdminDashboardScreen(),
                    AcademyStatsScreen(embedded: true),
                    SizedBox.shrink(),
                    BillingScreen(embedded: true),
                    ProfileScreen(),
                  ]
                : const [
                    DashboardScreen(),
                    AttendanceHomeScreen(embedded: true),
                    SizedBox.shrink(),
                    FeesLandingScreen(),
                    ProfileScreen(),
                  ],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        mode: _mode,
        socialIndex: _socialIndex,
        erpIndex: _erpIndex,
        canToggleErp: canToggle,
        isSuperAdmin: isSuperAdmin,
        onSocialTap: (i) => setState(() => _socialIndex = i),
        onErpTap: (i) => setState(() => _erpIndex = i),
        onMoreTap: () => showMoreMenu(context, ref, this),
        onSearchTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SearchProfilesScreen()),
        ),
        onToggle: () {
          // Both sides must actually be available - when the platform is set to one side only,
          // there is nowhere to toggle to.
          if (!canToggle) return;
          setState(() {
            _modeChosenByUser = true;
            _mode = _mode == AppMode.social ? AppMode.erp : AppMode.social;
          });
        },
      ),
    );
  }
}

class BottomNavBar extends StatefulWidget {
  const BottomNavBar({
    super.key,
    required this.mode,
    required this.socialIndex,
    required this.erpIndex,
    required this.canToggleErp,
    required this.isSuperAdmin,
    required this.onSocialTap,
    required this.onErpTap,
    required this.onMoreTap,
    required this.onSearchTap,
    required this.onToggle,
  });

  final AppMode mode;
  final int socialIndex;
  final int erpIndex;
  final bool canToggleErp;
  final bool isSuperAdmin;
  final ValueChanged<int> onSocialTap;
  final ValueChanged<int> onErpTap;
  final VoidCallback onMoreTap;
  final VoidCallback onSearchTap;
  final VoidCallback onToggle;

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

/// The four tab slots either side of the centre logo fade/slide/scale in with a 40ms stagger
/// (matching the reference's `navTabIn` keyframe) every time [AppMode] flips - the logo pops on
/// its own (see [_NavLogoToggle]); this is what makes the rest of the row read as answering that
/// pop rather than just snapping to a different icon set.
class _BottomNavBarState extends State<BottomNavBar> with SingleTickerProviderStateMixin {
  static const _itemDuration = Duration(milliseconds: 340);
  static const _staggerStep = Duration(milliseconds: 40);
  static const _slotCount = 4; // left0, left1, right0, actionItem
  static const _curve = Cubic(0.2, 0.85, 0.3, 1);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _itemDuration + _staggerStep * (_slotCount - 1),
  )..forward();

  @override
  void didUpdateWidget(covariant BottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _slotAnimation(int index) {
    final totalMs = _controller.duration!.inMilliseconds;
    final startMs = _staggerStep.inMilliseconds * index;
    final endMs = startMs + _itemDuration.inMilliseconds;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(startMs / totalMs, (endMs / totalMs).clamp(0.0, 1.0), curve: _curve),
    );
  }

  /// Wraps a slot's *content* in the fade/slide/scale-in - never the `Expanded` around it, which
  /// must stay a direct `Row` child or Flutter throws (an `Expanded` nested inside a `Transform`
  /// or `Opacity` isn't a direct child of the Flex that's meant to size it).
  Widget _staggerContent(int index, Widget child) {
    final animation = _slotAnimation(index);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, staggerChild) {
        final t = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - t)),
            child: Transform.scale(scale: 0.85 + 0.15 * t, child: staggerChild),
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSocial = widget.mode == AppMode.social;
    final currentIndex = isSocial ? widget.socialIndex : widget.erpIndex;

    // The ERP set differs for a Super Admin: they have no academy, so Batches/Fees are replaced by
    // the platform-level equivalents (see AppShellState's IndexedStack).
    final t = AppLocalizations.of(context);
    final erpLeftIcons = widget.isSuperAdmin
        ? [(Icons.insights_outlined, t.navPlatform), (Icons.account_balance_outlined, t.navAcademies)]
        : [(Icons.dashboard_outlined, t.navDashboard), (Icons.fact_check_outlined, 'Attendance')];
    final erpRightIcons = widget.isSuperAdmin
        ? [(Icons.receipt_long_outlined, t.navBilling), (Icons.apps_rounded, t.navMore)]
        : [(Icons.account_balance_wallet_outlined, t.navFees), (Icons.apps_rounded, t.navMore)];

    final leftIcons = isSocial
        ? [(Icons.dynamic_feed_outlined, t.navFeed), (Icons.celebration_outlined, t.navEvents)]
        : erpLeftIcons;
    // Both sides now carry exactly 2 left + 2 right icons around the centre toggle, so the two
    // modes line up pixel-for-pixel when you switch - Social's Profile moved to the app-bar
    // (mirroring ERP), freeing this slot for My Posts + Search.
    final rightIcons = isSocial
        ? [(Icons.grid_on_outlined, t.navMyPosts), (Icons.search, t.navSearch)]
        : erpRightIcons;

    Widget navItem(IconData icon, String label, int index, ValueChanged<int> onTap, int slot) {
      final selected = currentIndex == index;
      final color = selected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.45);
      return Expanded(
        child: InkWell(
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _staggerContent(
              slot,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 23),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(color: color, fontSize: 10.5)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Unlike the other four slots, this one triggers an action (ERP: opens the More sheet; Social:
    // pushes Search) rather than switching to a tab - it never has a "selected" state of its own,
    // so it always renders in the neutral colour.
    Widget actionItem(IconData icon, String label, VoidCallback onTap, int slot) {
      final color = colorScheme.onSurface.withValues(alpha: 0.45);
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _staggerContent(
              slot,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 23),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(color: color, fontSize: 10.5)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final palette = context.palette;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        height: 64,
        clipBehavior: Clip.none,
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.pill),
          boxShadow: AppShadows.dropdown,
        ),
        child: Row(
          children: [
            navItem(leftIcons[0].$1, leftIcons[0].$2, 0, isSocial ? widget.onSocialTap : widget.onErpTap, 0),
            navItem(leftIcons[1].$1, leftIcons[1].$2, 1, isSocial ? widget.onSocialTap : widget.onErpTap, 1),
            // Center is load-bearing: Expanded hands its child a TIGHT width (a fifth of the bar),
            // which on a wide desktop window is ~350px - the logo's own width is ignored and
            // ClipOval stretches it into a long ellipse. Center lets it keep its intrinsic size
            // while the slot still reserves an equal share of the row. The logo widget owns its own
            // opacity-when-disabled, lift, halo pulse and pop-on-toggle animation.
            Expanded(
              child: Center(
                child: _NavLogoToggle(
                  mode: widget.mode,
                  canToggle: widget.canToggleErp,
                  onTap: widget.onToggle,
                ),
              ),
            ),
            navItem(rightIcons[0].$1, rightIcons[0].$2, 3, isSocial ? widget.onSocialTap : widget.onErpTap, 2),
            actionItem(rightIcons[1].$1, rightIcons[1].$2, isSocial ? widget.onSearchTap : widget.onMoreTap, 3),
          ],
        ),
      ),
    );
  }
}

/// App-bar bell for the current module, with an unread-count badge. Tapping TOGGLES a dropdown
/// panel open/closed right under the bell - never a full page - and tapping outside (or the bell
/// again) closes it. Watching a Riverpod family per module means the badge auto-refreshes whenever
/// the notifications/unread providers are invalidated (e.g. after marking something read).
class _NotificationBell extends ConsumerStatefulWidget {
  const _NotificationBell({required this.module});

  final NotificationModule module;

  @override
  ConsumerState<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<_NotificationBell> {
  final _link = LayerLink();
  OverlayEntry? _overlayEntry;

  void _toggle() => _overlayEntry != null ? _close() : _open();

  void _open() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          // Full-screen invisible barrier - tapping anywhere outside the panel closes it.
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380, maxHeight: 440),
                child: SizedBox(
                  width: 380,
                  child: NotificationDropdownContent(module: widget.module, onClose: _close),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _close() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider(widget.module)).valueOrNull ?? 0;
    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: _toggle,
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(_overlayEntry != null ? Icons.notifications : Icons.notifications_outlined),
        ),
      ),
    );
  }
}

/// Quick theme cycling (system -> light -> dark -> system) right in the app bar - matches the
/// reference's header treatment. [ThemeModeController] already persists the choice to the
/// account (Phase 6 of the PRD), so this is just a faster path to the same setting the Settings
/// screen offers, not a second source of truth.
const _kThemeToggleOptions = [
  (mode: ThemeMode.system, icon: Icons.brightness_auto_outlined),
  (mode: ThemeMode.light, icon: Icons.light_mode_outlined),
  (mode: ThemeMode.dark, icon: Icons.dark_mode_outlined),
];

/// Collapsed: a single circular icon matching the current theme. Tapping it expands into a
/// 3-icon pill (system/light/dark) with the active mode picked out in gold, matching the
/// reference - picking any option applies it and collapses straight back.
class _ThemeToggleButton extends ConsumerStatefulWidget {
  const _ThemeToggleButton();

  @override
  ConsumerState<_ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends ConsumerState<_ThemeToggleButton> {
  bool _expanded = false;

  IconData _icon(ThemeMode mode) =>
      _kThemeToggleOptions.firstWhere((o) => o.mode == mode).icon;

  void _select(ThemeMode mode) {
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mode = ref.watch(themeModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: _expanded ? 104 : 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: AppRadii.all(AppRadii.pill),
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: _expanded
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final option in _kThemeToggleOptions)
                    _ThemeOptionDot(
                      icon: option.icon,
                      selected: option.mode == mode,
                      goldColor: palette.gold,
                      onTap: () => _select(option.mode),
                    ),
                ],
              )
            : InkWell(
                onTap: () => setState(() => _expanded = true),
                child: Icon(_icon(mode), size: 16, color: Colors.white),
              ),
      ),
    );
  }
}

class _ThemeOptionDot extends StatelessWidget {
  const _ThemeOptionDot({
    required this.icon,
    required this.selected,
    required this.goldColor,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color goldColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? goldColor : Colors.transparent,
        ),
        child: Icon(icon, size: 14, color: selected ? Colors.black : Colors.white),
      ),
    );
  }
}

/// The centre logo / mode-toggle button. Three animations layer on the same static ring, matching
/// the reference (nest-navigation-bar.jsx's `NestLogoButton` + its `nestPulse`/`logoSwapPop`
/// keyframes):
///  - a continuously pulsing halo behind the ring, coloured for whichever mode is active,
///  - a bouncy "pop" (scale + a little rotation) the instant [mode] actually flips,
///  - a quick press-scale, independent of both, driven by InkWell's own highlight state rather
///    than a second gesture recogniser (a nested GestureDetector would fight InkWell for the tap).
class _NavLogoToggle extends StatefulWidget {
  const _NavLogoToggle({required this.mode, required this.canToggle, required this.onTap});

  final AppMode mode;
  final bool canToggle;
  final VoidCallback onTap;

  @override
  State<_NavLogoToggle> createState() => _NavLogoToggleState();
}

class _NavLogoToggleState extends State<_NavLogoToggle> with TickerProviderStateMixin {
  // Not Cubic(0.34, 1.56, 0.64, 1) (the reference's CSS overshoot easing): that curve's whole
  // point is to swing past 1.0, which is fine as a CSS animation-timing-function but crashes here -
  // this curve drives a TweenSequence below, and TweenSequence.transform asserts its input stays
  // within [0, 1]. The bounce this was meant to add is already baked into the TweenSequence's own
  // values (1 -> 0.72 -> 1.12 -> 1), so the driving curve only needs to shape the pacing, not
  // overshoot a second time.
  static const _popCurve = Curves.easeOutCubic;

  late final AnimationController _haloController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();
  late final AnimationController _popController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  // Halo: scale 0.9->1.55 and opacity 0.55->0 over the first 70% of the cycle, then holds at that
  // (invisible) end state for the rest - mirrors the CSS keyframe's 0%/70%/100% stops.
  late final Animation<double> _haloScale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.55).chain(CurveTween(curve: Curves.easeOut)), weight: 70),
    TweenSequenceItem(tween: ConstantTween(1.55), weight: 30),
  ]).animate(_haloController);
  late final Animation<double> _haloOpacity = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.55, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 70),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
  ]).animate(_haloController);

  late final Animation<double> _popCurved = CurvedAnimation(parent: _popController, curve: _popCurve);
  // 1 -> 0.72 (compress in) -> 1.12 (overshoot out) -> 1 (settle), with a little rotation riding
  // along the same three segments - same shape as the reference's `logoSwapPop`.
  late final Animation<double> _popScale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.72), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.12), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 30),
  ]).animate(_popCurved);
  late final Animation<double> _popRotationDeg = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 8.0), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 8.0, end: -4.0), weight: 30),
    TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 30),
  ]).animate(_popCurved);

  @override
  void didUpdateWidget(covariant _NavLogoToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _popController.forward(from: 0);
  }

  @override
  void dispose() {
    _haloController.dispose();
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ringColor = widget.mode == AppMode.social ? palette.primary : palette.gold;

    return Opacity(
      opacity: widget.canToggle ? 1 : 0.35,
      // Lifted above the pill's top edge - matches the reference's raised, ringed owl button
      // rather than sitting flush with the other four icons.
      child: Transform.translate(
        offset: const Offset(0, -14),
        child: SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: _haloController,
                builder: (context, _) => Opacity(
                  opacity: _haloOpacity.value,
                  child: Transform.scale(
                    scale: _haloScale.value,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [ringColor.withValues(alpha: 0.3), ringColor.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: AnimatedBuilder(
                  animation: _popController,
                  builder: (context, child) => Transform.rotate(
                    angle: _popRotationDeg.value * math.pi / 180,
                    child: Transform.scale(scale: _popScale.value, child: child),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 54,
                    height: 54,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.bg,
                      border: Border.all(color: ringColor, width: 2),
                      boxShadow: AppShadows.focusGlow(ringColor),
                    ),
                    child: const ClipOval(
                      child: Image(image: AssetImage('assets/brand/owl_icon.png'), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

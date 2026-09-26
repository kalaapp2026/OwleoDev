import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/shell/domain/erp_action.dart';
import 'package:nest_fe/features/shell/presentation/app_shell.dart';

/// The Trainer/Admin "More" action grid: a bottom-sheet of every ERP action the caller's
/// role+feature grants allow, four to a row, each tile carrying its own accent colour rather than
/// a single neutral one - closer to how the rest of the app (stat tiles, category chips) already
/// colour-codes a grid of otherwise-similar cards. Visibility per tile is feature-gated the same
/// way the backend gates the endpoint itself - this is a convenience shortcut, not a second source
/// of truth; the backend still enforces every one of these via @RequiresFeature regardless of what
/// the client shows.
/// [shellState] is passed directly rather than found via `context.findAncestorStateOfType` -
/// this is called from AppShellState's own build() context (the nav bar's onMoreTap), and ancestor
/// lookup searches strictly above a context, never including the State that owns it. That lookup
/// works fine for the other places in the app that reach for AppShellState (they're genuinely
/// nested inside its body), but from here it would silently return null.
Future<void> showMoreMenu(BuildContext context, WidgetRef ref, AppShellState shellState) {
  final user = ref.read(sessionControllerProvider).user;
  if (user == null) return Future.value();

  // erpTabIndex-bound items (Dashboard/Attendance/Fees) are the bottom tab bar itself - never
  // duplicated inside "More".
  final visibleItems = kErpActions.where((item) => item.visibleFor(user) && item.route != null).toList();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // The scrim is drawn ourselves below (a blurred, tinted full-screen layer) - the framework's
    // own barrier stays invisible so it doesn't double up with it.
    barrierColor: Colors.transparent,
    builder: (sheetContext) {
      // showModalBottomSheet's Overlay sits above the whole Scaffold, including its
      // bottomNavigationBar - left alone, the sheet would cover the nav pill entirely. Reserving
      // its own height (64) plus its SafeArea minimum (8) plus a visual gap keeps it visible
      // underneath, the way the reference floats the sheet just above the bar rather than over it.
      final navBarReserve = 64 + 8 + 14 + MediaQuery.paddingOf(sheetContext).bottom;
      return _MoreSheetBody(items: visibleItems, shellState: shellState, navBarReserve: navBarReserve);
    },
  );
}

/// Layers extra polish on top of `showModalBottomSheet`'s own default slide-up transition (which
/// stays in effect - see [showMoreMenu]): the scrim fades in, the card fades in, and once the card
/// has mostly landed the tiles pop in with a stagger (`moreTileIn`, delayed to start once the card
/// has mostly landed). Deliberately no extra vertical motion on the card itself - the route's own
/// slide already carries the whole sheet (including the bottom nav bar copy, which should read as
/// stationary) up from the bottom; a second translate on top of that read as two things rising in
/// sequence instead of one.
class _MoreSheetBody extends StatefulWidget {
  const _MoreSheetBody({required this.items, required this.shellState, required this.navBarReserve});

  final List<ErpAction> items;
  final AppShellState shellState;
  final double navBarReserve;

  @override
  State<_MoreSheetBody> createState() => _MoreSheetBodyState();
}

class _MoreSheetBodyState extends State<_MoreSheetBody> with SingleTickerProviderStateMixin {
  static const _cardDuration = Duration(milliseconds: 320);
  static const _cardCurve = Cubic(0.16, 1, 0.3, 1);
  // 320ms * 0.55 - tiles start popping once the card is mostly settled, same offset the reference
  // uses (`SHEET_ANIM_MS * 0.55`).
  static const _tileStartDelay = Duration(milliseconds: 176);
  static const _tileStep = Duration(milliseconds: 45);
  static const _tileDuration = Duration(milliseconds: 360);
  static const _tileCurve = Cubic(0.34, 1.56, 0.64, 1);

  late final AnimationController _controller;
  late final Animation<double> _backdropOpacity;
  late final Animation<double> _cardProgress;

  @override
  void initState() {
    super.initState();
    final lastTileEndMs = widget.items.isEmpty
        ? _cardDuration.inMilliseconds
        : _tileStartDelay.inMilliseconds +
            _tileStep.inMilliseconds * (widget.items.length - 1) +
            _tileDuration.inMilliseconds;
    final totalMs = math.max(_cardDuration.inMilliseconds, lastTileEndMs);
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: totalMs))..forward();
    _backdropOpacity = CurvedAnimation(
      parent: _controller,
      curve: Interval(0, (200 / totalMs).clamp(0.0, 1.0), curve: Curves.easeOut),
    );
    _cardProgress = CurvedAnimation(
      parent: _controller,
      curve: Interval(0, (_cardDuration.inMilliseconds / totalMs).clamp(0.0, 1.0), curve: _cardCurve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _tileAnimation(int index) {
    final totalMs = _controller.duration!.inMilliseconds;
    final startMs = _tileStartDelay.inMilliseconds + _tileStep.inMilliseconds * index;
    final endMs = startMs + _tileDuration.inMilliseconds;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval((startMs / totalMs).clamp(0.0, 1.0), (endMs / totalMs).clamp(0.0, 1.0), curve: _tileCurve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetContext = context;
    final palette = context.palette;

    // Forced to the full viewport height: a Stack under a scroll-controlled bottom sheet's loose
    // constraints sizes itself to its tallest non-positioned child (here, just the card) rather
    // than filling the screen, so without this the Positioned children below would be measured
    // against a box barely taller than the card itself - never reaching down to where the real
    // nav bar sits, no matter what "bottom:" value they're given.
    return SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height,
      width: double.infinity,
      child: Stack(
        children: [
          // Blurs and dims the dashboard behind rather than just tinting it - frosted-glass scrim,
          // matching the reference. Drawn ourselves (rather than via barrierColor) because
          // BackdropFilter needs to sit in the widget tree above the content it blurs. Covers the
          // full screen (including where the nav bar sits) rather than stopping short of it: the
          // nav bar copy painted below is on top of this layer in the Stack, so it stays sharp
          // regardless of what's blurred beneath it.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _backdropOpacity,
              builder: (context, child) => Opacity(opacity: _backdropOpacity.value, child: child),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(color: Colors.black.withValues(alpha: 0.25)),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              // Fade only, deliberately no translate: the *route itself* already slides this
              // whole sheet up from the bottom (showModalBottomSheet's own default transition,
              // still in effect here - see the class doc). Layering a second upward slide on top
              // of that read as two separate things rising from the bottom in sequence, including
              // the nav bar copy below, which should only ever look like it's already in place.
              child: AnimatedBuilder(
                animation: _cardProgress,
                builder: (context, child) {
                  final t = _cardProgress.value.clamp(0.0, 1.0);
                  return Opacity(opacity: t, child: child);
                },
                child: Container(
                  margin: EdgeInsets.fromLTRB(12, 0, 12, widget.navBarReserve),
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadii.all(AppRadii.x4l),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'More',
                              style: TextStyle(
                                fontSize: AppType.title,
                                fontWeight: AppType.heavy,
                                color: palette.text,
                              ),
                            ),
                          ),
                          _CloseButton(onTap: () => Navigator.of(sheetContext).pop()),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: AppSpacing.xl,
                        crossAxisSpacing: AppSpacing.sm,
                        childAspectRatio: 0.82,
                        children: [
                          for (var i = 0; i < widget.items.length; i++)
                            _StaggeredTile(
                              animation: _tileAnimation(i),
                              child: _MoreMenuTile(
                                item: widget.items[i],
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  final item = widget.items[i];
                                  if (item.erpTabIndex != null) {
                                    widget.shellState.goToErpTab(item.erpTabIndex!);
                                  } else if (item.route != null) {
                                    sheetContext.push(item.route!);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // A real copy of the app's own bottom nav bar, on top of the blur - see
          // AppShellState.buildOverlayBottomNav for why the sheet can't just rely on the real one
          // showing through underneath.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: widget.shellState.buildOverlayBottomNav(
              onNavigate: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade + scale-in for one More-grid tile, driven by a caller-supplied slice of the sheet's shared
/// controller (see [_MoreSheetBodyState._tileAnimation]) rather than owning its own ticker - one
/// controller for the whole grid keeps every tile's timing locked to the same clock.
class _StaggeredTile extends StatelessWidget {
  const _StaggeredTile({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, tile) {
        final t = animation.value.clamp(0.0, 1.0);
        return Opacity(opacity: t, child: Transform.scale(scale: 0.7 + 0.3 * t, child: tile));
      },
      child: child,
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.md),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: palette.border),
        ),
        child: Icon(Icons.close, size: 16, color: palette.textMuted),
      ),
    );
  }
}

/// One accent per tile, cycling through the same colour set the rest of the app already uses for
/// category dots and stat tiles - so a new module added to [kErpActions] never needs a colour
/// decision made up on the spot.
(Color, Color) _accentFor(AppPalette palette, String label) => switch (label) {
      'Courses' => (palette.violet, palette.violetSoft),
      'Batches' => (palette.paidManual, palette.paidManualSoft),
      'Batch Scheduling' => (palette.gold, palette.goldSoft),
      'Events' => (palette.gateway, palette.gatewaySoft),
      'Messages' => (palette.magenta, palette.magentaSoft),
      'Study Material' => (palette.primary, palette.primarySoft),
      'Users' => (palette.sage, palette.sageSoft),
      'Students' => (palette.coral, palette.coralSoft),
      'Academy Profile' => (palette.gold, palette.goldSoft),
      _ => (palette.textMuted, palette.surfaceHigh),
    };

class _MoreMenuTile extends StatelessWidget {
  const _MoreMenuTile({required this.item, required this.onTap});

  final ErpAction item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (color, soft) = _accentFor(palette, item.label);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: AppRadii.all(AppRadii.xl),
            ),
            child: Icon(item.icon, color: color, size: 22),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.xs,
              fontWeight: AppType.semi,
              color: palette.textMuted,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

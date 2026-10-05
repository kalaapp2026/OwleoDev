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
    // We are the only way in or out: no drag-to-dismiss, no barrier-tap-to-dismiss racing against
    // our own close handlers. Every dismissal goes through _MoreSheetBodyState._close, which
    // reverses the shared animation BEFORE popping - if the framework's own barrier could also
    // pop the route directly, that sequencing could be bypassed.
    isDismissible: false,
    enableDrag: false,
    // Disables the framework's own slide-up/down transition entirely, in both directions.
    // _MoreSheetBody drives 100% of the visible motion itself from one shared controller - see
    // its class doc for why layering our fades under that separate, uncoordinated transition was
    // the root cause of the open/close bugs this replaced.
    sheetAnimationStyle: const AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero),
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

/// Owns the entire open/close animation itself - showMoreMenu disables the framework's own
/// slide-up/down transition (see there) precisely so nothing else is moving the sheet's content
/// underneath us. Backdrop opacity, backdrop blur strength, and the card's own height/opacity are
/// all driven from the SAME [_reveal] animation, which is why they can't go out of sync with each
/// other. [_controller] never fights another clock: [_close] reverses it and awaits that reverse
/// BEFORE popping the route, so nothing is ever torn down while still visible.
///
/// The card grows from the bottom rather than sliding or fading in place - [Align.heightFactor]
/// on the fully-laid-out card reveals it from its own bottom edge upward, so the bottom stays
/// pinned and the top is what visibly rises, matching the reference. This also means the card's
/// height never needs to be measured up front: Align lets it lay out at its natural size every
/// frame regardless of how much of it is currently revealed.
class _MoreSheetBody extends StatefulWidget {
  const _MoreSheetBody({required this.items, required this.shellState, required this.navBarReserve});

  final List<ErpAction> items;
  final AppShellState shellState;
  final double navBarReserve;

  @override
  State<_MoreSheetBody> createState() => _MoreSheetBodyState();
}

class _MoreSheetBodyState extends State<_MoreSheetBody> with SingleTickerProviderStateMixin {
  // The panel's own rise: bottom pinned, top edge growing up to full height, backdrop dimming and
  // blurring in step with it - all three read off the same [_reveal] value, over the same span.
  static const _revealDuration = Duration(milliseconds: 140);
  static const _revealCurve = Curves.easeOut;
  // Close is a plain, fast fade - no stagger-out, nothing to sequence. A separate reverseCurve
  // (rather than reusing _revealCurve backwards) is what keeps this starting immediately at
  // whatever value forward left off, instead of holding at 1.0 through the portion of the curve
  // _revealCurve's Interval reserved for the tile stagger before it even starts moving.
  static const _closeDuration = Duration(milliseconds: 130);
  static const _closeCurve = Curves.easeIn;
  // Tiles start once the panel has finished revealing, not mid-way through it - the panel itself
  // is now a short, snappy grow rather than a long fade, so there's no "mostly settled" partway
  // point left to key off of the way the previous timing did.
  static const _tileStartDelay = Duration(milliseconds: 140);
  static const _tileStep = Duration(milliseconds: 45);
  static const _tileDuration = Duration(milliseconds: 360);
  static const _tileCurve = Cubic(0.34, 1.56, 0.64, 1);

  late final AnimationController _controller;
  late final Animation<double> _reveal;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final lastTileEndMs = widget.items.isEmpty
        ? _revealDuration.inMilliseconds
        : _tileStartDelay.inMilliseconds +
            _tileStep.inMilliseconds * (widget.items.length - 1) +
            _tileDuration.inMilliseconds;
    final totalMs = math.max(_revealDuration.inMilliseconds, lastTileEndMs);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
      reverseDuration: _closeDuration,
    )..forward();
    _reveal = CurvedAnimation(
      parent: _controller,
      curve: Interval(0, (_revealDuration.inMilliseconds / totalMs).clamp(0.0, 1.0), curve: _revealCurve),
      reverseCurve: _closeCurve,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The one path every dismissal goes through - the X, the backdrop, and "More" tapped again
  /// all call this rather than popping directly. Reversing (and awaiting it) before popping means
  /// the route is only ever removed once it's already invisible, so there's nothing left to tear
  /// down mid-flight - that abrupt teardown of a still-live, still-blurring backdrop was the
  /// likeliest source of the colour flash this replaced. [_closing] just guards against two taps
  /// (say, the backdrop and the X in the same frame) each starting their own reverse and then
  /// both trying to pop once it finishes.
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    if (mounted) Navigator.of(context).pop();
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
          // regardless of what's blurred beneath it. The blur strength itself ramps with [_reveal]
          // (not just the opacity) - wrapping a constant-strength blur in Opacity alone still
          // composites at full strength from the first visible frame, which is what read as the
          // blur "snapping" on rather than easing in.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _reveal,
              builder: (context, child) {
                final t = _reveal.value.clamp(0.0, 1.0);
                return Opacity(
                  opacity: t,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
                      child: Container(color: Colors.black.withValues(alpha: 0.25)),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              // Grows from the bottom rather than sliding or fading in place - see the class doc
              // for why: Align's heightFactor reveals the (fully laid-out, natural-height) card
              // from its own bottom edge upward, in lockstep with the same [_reveal] value driving
              // the backdrop above, so the two can never drift apart.
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (context, child) {
                  final t = _reveal.value.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: t,
                    child: ClipRect(
                      child: Align(alignment: Alignment.bottomCenter, heightFactor: t, child: child),
                    ),
                  );
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
                          _CloseButton(onTap: _close),
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
              onNavigate: _close,
              moreActive: true,
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

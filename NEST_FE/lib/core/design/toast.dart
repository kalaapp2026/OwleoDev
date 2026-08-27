import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// The design's confirmation toast: floats above the content, auto-dismisses.
///
/// Not a SnackBar. Material's version docks to the very bottom of the Scaffold, which on this app
/// puts it behind the nav bar, and it carries its own theming that fights the palette.
class AppToast extends StatelessWidget {
  const AppToast({super.key, required this.message, this.icon = Icons.check_circle_outline});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.primary),
        boxShadow: AppShadows.dialog,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: palette.primary),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppType.lg,
                fontWeight: AppType.semi,
                color: palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows an [AppToast] floating above the current screen for [duration].
///
/// Returns immediately. Repeated calls replace the visible toast rather than queueing, so a run of
/// quick actions shows the latest result instead of making the user wait out a backlog.
void showAppToast(BuildContext context, String message,
    {Duration duration = const Duration(milliseconds: 2200)}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  _currentToast?.remove();
  _currentToast = null;
  _toastTimer?.cancel();

  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: AppSpacing.xl,
      right: AppSpacing.xl,
      bottom: MediaQuery.of(context).padding.bottom + 90,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: _ToastFade(child: AppToast(message: message)),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  _currentToast = entry;
  _toastTimer = Timer(duration, () {
    if (_currentToast == entry) {
      entry.remove();
      _currentToast = null;
    }
  });
}

OverlayEntry? _currentToast;
Timer? _toastTimer;

class _ToastFade extends StatefulWidget {
  const _ToastFade({required this.child});

  final Widget child;

  @override
  State<_ToastFade> createState() => _ToastFadeState();
}

class _ToastFadeState extends State<_ToastFade> {
  double _opacity = 0;
  double _offset = 10;

  @override
  void initState() {
    super.initState();
    // One frame at the starting values so the transition has something to animate from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _opacity = 1;
          _offset = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: AppMotion.toast,
      child: AnimatedSlide(
        offset: Offset(0, _offset / 100),
        duration: AppMotion.toast,
        curve: AppMotion.enter,
        child: widget.child,
      ),
    );
  }
}

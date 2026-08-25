import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';

/// Press feedback for the refreshed design: a brief scale-down on touch.
///
/// The prototype applies this globally via `button:not([data-noscale]):active { scale(0.96) }`,
/// with an opt-out for the flip toggle (scaling a 3D-rotating element looks wrong). Flutter has
/// no global equivalent, so it becomes an explicit wrapper - which is arguably better, since the
/// opt-out is now a matter of simply not using it rather than a magic attribute.
///
/// Uses [Listener] rather than [GestureDetector] for the press state so it doesn't compete in the
/// gesture arena: a [Pressable] inside a scrollable must shrink on touch AND still let the scroll
/// win if the finger moves. A GestureDetector claiming the down event would break that.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = AppMotion.pressScale,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// Clips the ripple when the child is a rounded card.
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && widget.onTap != null) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1.0,
          duration: AppMotion.press,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The prototype's 36x36 rounded-square icon button (back arrow, calendar steppers).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 36,
    this.iconSize = 18,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disabled = onTap == null;
    final button = Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Icon(
          icon,
          size: iconSize,
          // Disabled reads as faint rather than greyed - on this palette a grey would sit at
          // almost the same luminance as the enabled colour and not read as disabled at all.
          color: disabled ? palette.textFaint : (color ?? palette.text),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

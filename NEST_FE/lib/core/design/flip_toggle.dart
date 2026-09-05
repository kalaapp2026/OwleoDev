import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// A flip-clock style toggle: the button closes to edge-on, swaps its content while invisible,
/// then opens back up showing the new state.
///
/// The critical detail, and the reason this isn't just an AnimatedSwitcher with a rotation: it
/// **never rotates past 90 degrees in either direction**. It closes to +90 (edge-on, zero width),
/// jumps instantly to -90 while invisible, then opens to 0. A naive 0->180 flip would show the
/// label mirrored and upside-down through the middle of the animation.
///
/// Deliberately generic - it knows nothing about payments. The fees module supplies the labels
/// and colours; a batch screen could use the same widget for active/inactive.
class FlipToggle extends StatefulWidget {
  const FlipToggle({
    super.key,
    required this.isOn,
    required this.onLabel,
    required this.offLabel,
    this.onTap,
    this.onColor,
    this.onSoftColor,
    this.offColor,
    this.offSoftColor,
    this.width = 118,
    this.height = 34,
    this.onIcon,
    this.offIcon,
  });

  final bool isOn;
  final String onLabel;
  final String offLabel;
  final VoidCallback? onTap;

  final Color? onColor;
  final Color? onSoftColor;
  final Color? offColor;
  final Color? offSoftColor;

  /// Overrides the default tick/cross. Attendance uses filled circles so the toggle matches the
  /// Present/Absent icons used everywhere else on that screen.
  final IconData? onIcon;
  final IconData? offIcon;

  /// Fixed by default. The label changes length between states ("Mark Paid" / "Mark Not Paid"),
  /// and letting the button resize mid-flip makes the whole list row jump.
  final double width;
  final double height;

  @override
  State<FlipToggle> createState() => _FlipToggleState();
}

class _FlipToggleState extends State<FlipToggle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// What is currently *rendered*, which lags [widget.isOn] until the halfway point.
  late bool _displayOn;

  @override
  void initState() {
    super.initState();
    _displayOn = widget.isOn;
    _controller = AnimationController(vsync: this, duration: AppMotion.flipHalf);
  }

  @override
  void didUpdateWidget(covariant FlipToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOn != oldWidget.isOn && widget.isOn != _displayOn) {
      _flip();
    }
  }

  Future<void> _flip() async {
    // Close to edge-on.
    await _controller.forward(from: 0);
    if (!mounted) return;
    // Swap content while the button has zero apparent width, so the change is unseen.
    setState(() => _displayOn = widget.isOn);
    // Open from the opposite edge. reverse() replays the same curve backwards, and the sign
    // flip in the transform below turns that into "opening from the other side".
    await _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final onFg = widget.onColor ?? palette.paidManual;
    final onBg = widget.onSoftColor ?? palette.paidManualSoft;
    final offFg = widget.offColor ?? palette.notPaid;
    final offBg = widget.offSoftColor ?? palette.notPaidSoft;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 0 -> 90 degrees while closing; the same values read as -90 -> 0 while opening because
          // the content has already been swapped at the turn.
          final angle = _controller.value * (math.pi / 2) * (_displayOn == widget.isOn ? -1 : 1);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002) // perspective, matching the prototype's `perspective: 500`
              ..rotateX(angle),
            child: child,
          );
        },
        child: AnimatedContainer(
          // Colour cross-fades slower than the rotation on purpose, so it reads as continuous
          // rather than snapping at the halfway swap.
          duration: AppMotion.flipColor,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: _displayOn ? onBg : offBg,
            borderRadius: AppRadii.all(AppRadii.md),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _displayOn
                    ? (widget.onIcon ?? Icons.check)
                    : (widget.offIcon ?? Icons.close),
                size: 13,
                color: _displayOn ? onFg : offFg,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  _displayOn ? widget.onLabel : widget.offLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.sm,
                    fontWeight: AppType.bold,
                    color: _displayOn ? onFg : offFg,
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

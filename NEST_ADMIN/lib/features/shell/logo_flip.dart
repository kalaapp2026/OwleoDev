import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

const _hqLogo = 'assets/brand/logo_full.jpg';
const _socialLogo = 'assets/brand/logo_face.jpg';

String logoAsset({required bool social}) => social ? _socialLogo : _hqLogo;
Color ringColor({required bool social}) => social ? Hq.primary : Hq.gold;

/// The coin-flip that switches between Owleo HQ and Owleo Social, the same sequence as the
/// academy app and the prototype: the logo lifts to the middle, flips to its other face, says
/// hello, then flies home. [swap] is called at the midpoint of the flip, when the face is edge-on.
void playLogoFlip(
  BuildContext context, {
  required Rect from,
  required bool toSocial,
  required VoidCallback swap,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlipOverlay(from: from, toSocial: toSocial, swap: swap, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _FlipOverlay extends StatefulWidget {
  const _FlipOverlay({required this.from, required this.toSocial, required this.swap, required this.onDone});

  final Rect from;
  final bool toSocial;
  final VoidCallback swap;
  final VoidCallback onDone;

  @override
  State<_FlipOverlay> createState() => _FlipOverlayState();
}

class _FlipOverlayState extends State<_FlipOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _swapped = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_swapped && _c.value >= .28) {
        _swapped = true;
        widget.swap();
      }
    });
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const coin = 132.0;
    final center = Rect.fromLTWH((size.width - coin) / 2, (size.height - coin) / 2 - 46, coin, coin);
    final fromSocial = !widget.toSocial;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final out = Curves.easeOutCubic.transform(_seg(t, 0, .17));
        final back = Curves.easeInOutCubic.transform(_seg(t, .75, 1));
        final rect = t < .75 ? Rect.lerp(widget.from, center, out)! : Rect.lerp(center, widget.from, back)!;

        // 0 -> 90deg on the old face, then 90 -> 0 on the new one.
        final flipA = _seg(t, .17, .28), flipB = _seg(t, .28, .39);
        final angle = t < .28 ? flipA * math.pi / 2 : (1 - flipB) * math.pi / 2;
        final showingNew = t >= .28;
        final social = showingNew ? widget.toSocial : fromSocial;

        final backdrop = t < .75 ? _seg(t, 0, .15) : 1 - _seg(t, .75, 1);
        final text = t < .7 ? _seg(t, .39, .45) : 1 - _seg(t, .7, .75);

        return IgnorePointer(
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: const Color(0xFF04070E).withValues(alpha: .82 * backdrop))),
              Positioned.fromRect(
                rect: rect,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 1 / 700)
                    ..rotateY(angle),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Hq.bg,
                      border: Border.all(color: ringColor(social: social), width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 6))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(logoAsset(social: social), fit: BoxFit.cover),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: center.bottom + 22 + (1 - text) * 10,
                child: Opacity(
                  opacity: text,
                  child: Center(
                    child: Text(
                      widget.toSocial ? 'Welcome to Owleo Social' : 'Welcome back to Owleo HQ',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Hq.text, decoration: TextDecoration.none),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

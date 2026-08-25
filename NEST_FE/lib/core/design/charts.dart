import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';

/// Collection progress: a filled track with a gradient sweep.
///
/// The [compact] variant drops the "Collection progress / N of M paid" header and thins the bar,
/// for use inside a card that already labels itself.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.paid,
    required this.total,
    this.compact = false,
    this.label,
    this.trailingLabel,
  });

  final int paid;
  final int total;
  final bool compact;
  final String? label;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // total can legitimately be 0 (a batch with no students yet) - guard rather than divide.
    final fraction = total <= 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label ?? 'Collection progress',
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.medium,
                  color: palette.textMuted,
                ),
              ),
              Text(
                trailingLabel ?? '$paid/$total paid',
                style: TextStyle(
                  fontSize: AppType.smd,
                  fontWeight: AppType.bold,
                  color: palette.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        ClipRRect(
          borderRadius: AppRadii.all(AppRadii.xs),
          child: SizedBox(
            height: compact ? 6 : 8,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: palette.surfaceHigh)),
                // Animates on value change so recording a payment visibly moves the bar rather
                // than snapping - the feedback is the point.
                AnimatedFractionallySizedBox(
                  duration: AppMotion.progress,
                  curve: Curves.easeOut,
                  widthFactor: fraction,
                  heightFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [palette.primaryDim, palette.primary]),
                      borderRadius: AppRadii.all(AppRadii.xs),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A ring showing a percentage, with the figure in the middle.
///
/// Drawn with a [CustomPainter] rather than a charting package: it's two arcs and a label, and
/// pulling in fl_chart for this would cost more than it saves. The sweep animates from wherever
/// it currently is, so a payment nudges the ring forward instead of redrawing it.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.percent,
    this.color,
    this.size = 56,
    this.strokeWidth = 6,
  });

  /// 0-100. Clamped, so a caller that computes 103% from rounding doesn't overdraw the ring.
  final double percent;
  final Color? color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clamped = percent.clamp(0.0, 100.0);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: clamped),
        duration: AppMotion.donut,
        curve: Curves.easeOut,
        builder: (context, value, _) => CustomPaint(
          painter: _DonutPainter(
            percent: value,
            color: color ?? palette.revenue,
            track: palette.surfaceHigh,
            strokeWidth: strokeWidth,
          ),
          child: Center(
            child: Text(
              '${value.round()}%',
              style: TextStyle(
                fontSize: AppType.xs,
                fontWeight: AppType.heavy,
                color: palette.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.percent,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double percent;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (percent <= 0) return;

    final sweepPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // 12 o'clock, matching the prototype's rotate(-90)
      (percent / 100) * 2 * math.pi,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.percent != percent || old.color != color || old.track != track;
}

import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_colors.dart';

enum OwleoWordmarkSize { small, large }

/// Brand mark used on the login screen and app bar: the owl app-icon glyph plus the
/// "Owleo / NEST" wordmark from the approved brand mockups. The owl is drawn with
/// CustomPainter rather than a bundled PNG - swap in the real exported icon asset
/// (assets/brand/owl_icon.png) once the designer hands off final files; this keeps the
/// silhouette recognisable in the meantime without a placeholder-image dependency.
class OwleoWordmark extends StatelessWidget {
  const OwleoWordmark({super.key, this.size = OwleoWordmarkSize.small});

  final OwleoWordmarkSize size;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == OwleoWordmarkSize.large;
    final iconSize = isLarge ? 64.0 : 34.0;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OwlIcon(size: iconSize, accent: colorScheme.primary),
        SizedBox(width: isLarge ? 14 : 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Owleo',
              style: TextStyle(
                fontSize: isLarge ? 34 : 19,
                fontWeight: FontWeight.w800,
                height: 1.0,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'NEST',
              style: TextStyle(
                fontSize: isLarge ? 14 : 9,
                fontWeight: FontWeight.w700,
                letterSpacing: isLarge ? 5 : 3,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OwlIcon extends StatelessWidget {
  const _OwlIcon({required this.size, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightIconBg,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      padding: EdgeInsets.all(size * 0.16),
      child: CustomPaint(painter: _OwlFacePainter(accent: accent)),
    );
  }
}

/// Minimal geometric owl face: two round eyes, a triangular beak, and a swept underline
/// standing in for the wing/scarf flourish in the brand mockups.
class _OwlFacePainter extends CustomPainter {
  _OwlFacePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final eyeWhite = Paint()..color = Colors.white;
    final eyePupil = Paint()..color = const Color(0xFF14181A);
    final beak = Paint()..color = const Color(0xFFFFB020);
    final underline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.09
      ..strokeCap = StrokeCap.round;

    final eyeRadius = w * 0.24;
    final leftEyeCenter = Offset(w * 0.28, h * 0.36);
    final rightEyeCenter = Offset(w * 0.72, h * 0.36);

    canvas.drawCircle(leftEyeCenter, eyeRadius, eyeWhite);
    canvas.drawCircle(rightEyeCenter, eyeRadius, eyeWhite);
    canvas.drawCircle(leftEyeCenter, eyeRadius * 0.42, eyePupil);
    canvas.drawCircle(rightEyeCenter, eyeRadius * 0.42, eyePupil);

    final beakPath = Path()
      ..moveTo(w * 0.5, h * 0.5)
      ..lineTo(w * 0.42, h * 0.66)
      ..lineTo(w * 0.58, h * 0.66)
      ..close();
    canvas.drawPath(beakPath, beak);

    final underlinePath = Path()
      ..moveTo(w * 0.18, h * 0.86)
      ..quadraticBezierTo(w * 0.5, h * 1.0, w * 0.82, h * 0.86);
    canvas.drawPath(underlinePath, underline);
  }

  @override
  bool shouldRepaint(covariant _OwlFacePainter oldDelegate) => oldDelegate.accent != accent;
}

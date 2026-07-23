import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// A warm, stylised sunburst inspired by African heritage imagery.
///
/// Draws concentric rings of rays in gold and cream behind the hero section
/// of the historical-records search screen. No external assets required.
class AfricanSunburst extends StatelessWidget {
  const AfricanSunburst({
    super.key,
    this.size = 280,
    this.rayCount = 32,
    this.child,
  });

  final double size;
  final int rayCount;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _SunburstPainter(rayCount: rayCount),
        child: child,
      ),
    );
  }
}

class _SunburstPainter extends CustomPainter {
  _SunburstPainter({required this.rayCount});

  final int rayCount;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2;

    // Concentric warm rings.
    final List<Color> ringColors = <Color>[
      AppColors.sunGold.withValues(alpha: 0.28),
      AppColors.sunGold.withValues(alpha: 0.18),
      AppColors.sunGoldLight.withValues(alpha: 0.12),
    ];
    for (int i = 0; i < ringColors.length; i++) {
      final double r = radius - (i * 22);
      if (r <= 0) continue;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = ringColors[i]
          ..style = PaintingStyle.fill,
      );
    }

    // Radiating tapered rays.
    final Paint rayPaint = Paint()
      ..color = AppColors.sunGold.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final Paint accentRayPaint = Paint()
      ..color = AppColors.sunGold.withValues(alpha: 0.32)
      ..style = PaintingStyle.fill;

    final double step = 2 * math.pi / rayCount;
    for (int i = 0; i < rayCount; i++) {
      final double angle = i * step;
      final bool isAccent = i % 4 == 0;
      final double rayLength = radius * (isAccent ? 1.0 : 0.82);
      final double baseWidth = radius * (isAccent ? 0.07 : 0.04);

      final Path path = Path();
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);

      // Inner base.
      final Offset inner =
          center + Offset(cosA * radius * 0.35, sinA * radius * 0.35);
      // Tip.
      final Offset tip = center + Offset(cosA * rayLength, sinA * rayLength);
      // Perpendicular for width.
      final Offset perp = Offset(-sinA * baseWidth / 2, cosA * baseWidth / 2);

      path
        ..moveTo(inner.dx + perp.dx, inner.dy + perp.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(inner.dx - perp.dx, inner.dy - perp.dy)
        ..close();

      canvas.drawPath(path, isAccent ? accentRayPaint : rayPaint);
    }

    // Dotted inner ring.
    final int dotCount = 24;
    final double dotRadius = radius * 0.28;
    final Paint dotPaint = Paint()
      ..color = AppColors.sunGold.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < dotCount; i++) {
      final double a = i * (2 * math.pi / dotCount);
      final Offset dot =
          center + Offset(math.cos(a) * dotRadius, math.sin(a) * dotRadius);
      final bool isMajorDot = i % 4 == 0;
      canvas.drawCircle(dot, isMajorDot ? 4.5 : 2.5, dotPaint);
    }

    // Solid centre glow.
    canvas.drawCircle(
      center,
      radius * 0.18,
      Paint()
        ..color = AppColors.sunGoldLight.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) =>
      oldDelegate.rayCount != rayCount;
}

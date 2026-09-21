import 'package:flutter/material.dart';

/// Draws the "Your tree progress" completion ring — a plain percentage arc,
/// not tied to any specific data source (the dashboard computes the
/// percentage; this just renders it).
class TreeProgressRingPainter extends CustomPainter {
  const TreeProgressRingPainter({
    required this.percent,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 10,
  });

  /// 0.0–1.0.
  final double percent;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 6.28319, false, track);

    final Paint progress = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const double start = -1.5708; // 12 o'clock
    final double sweep = 6.28319 * percent.clamp(0.0, 1.0);
    canvas.drawArc(rect, start, sweep, false, progress);
  }

  @override
  bool shouldRepaint(TreeProgressRingPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

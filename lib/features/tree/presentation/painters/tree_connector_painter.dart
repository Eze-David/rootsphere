import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../layout/tree_layout.dart';

/// Paints the parent-child and spouse connectors behind the person cards.
///
/// Performs viewport culling: connectors whose bounds fall entirely outside
/// [visibleRect] (in scene coordinates) are skipped. This keeps painting cheap
/// for large trees where most of the graph is off-screen.
class TreeConnectorPainter extends CustomPainter {
  TreeConnectorPainter({
    required this.connectors,
    required this.visibleRect,
    this.lineColor = AppColors.border,
    this.spouseColor = AppColors.textTertiary,
  });

  final List<TreeConnector> connectors;
  final Rect visibleRect;
  final Color lineColor;
  final Color spouseColor;

  /// Corner radius used to round the elbow connectors.
  static const double _corner = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final parentPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final spousePaint = Paint()
      ..color = spouseColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final buttCapPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    final inflated = visibleRect.inflate(64);

    for (final c in connectors) {
      if (!c.bounds.overlaps(inflated)) continue; // viewport culling
      if (c.points.length < 2) continue;
      final Paint paint = !c.roundCap
          ? buttCapPaint
          : (c.isSpouse ? spousePaint : parentPaint);
      canvas.drawPath(_roundedPolyline(c.points), paint);
    }
  }

  /// Builds a polyline with rounded corners at each interior vertex.
  Path _roundedPolyline(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final Offset prev = pts[i - 1];
      final Offset cur = pts[i];
      final Offset next = pts[i + 1];

      final double inLen = (cur - prev).distance;
      final double outLen = (next - cur).distance;
      final double half = inLen < outLen ? inLen / 2 : outLen / 2;
      final double r = _corner < half ? _corner : half;

      final Offset before = cur - _unit(cur - prev) * r;
      final Offset after = cur + _unit(next - cur) * r;

      path.lineTo(before.dx, before.dy);
      path.quadraticBezierTo(cur.dx, cur.dy, after.dx, after.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  Offset _unit(Offset v) {
    final double d = v.distance;
    return d == 0 ? Offset.zero : v / d;
  }

  @override
  bool shouldRepaint(covariant TreeConnectorPainter old) {
    return old.connectors != connectors ||
        old.visibleRect != visibleRect ||
        old.lineColor != lineColor;
  }
}

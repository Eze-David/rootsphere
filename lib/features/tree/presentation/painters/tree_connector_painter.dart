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

    final inflated = visibleRect.inflate(64);

    for (final c in connectors) {
      if (!c.bounds.overlaps(inflated)) continue; // viewport culling
      if (c.points.length < 2) continue;

      final path = Path()..moveTo(c.points.first.dx, c.points.first.dy);
      for (int i = 1; i < c.points.length; i++) {
        path.lineTo(c.points[i].dx, c.points[i].dy);
      }
      canvas.drawPath(path, c.isSpouse ? spousePaint : parentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TreeConnectorPainter old) {
    return old.connectors != connectors ||
        old.visibleRect != visibleRect ||
        old.lineColor != lineColor;
  }
}

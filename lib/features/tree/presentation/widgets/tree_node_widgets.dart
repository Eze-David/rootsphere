import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// An empty "Add father / Add mother" placeholder card with a dashed border and
/// a circular `+` affordance. Tapping it starts the add-parent flow.
class PlaceholderSlotWidget extends StatefulWidget {
  const PlaceholderSlotWidget({
    super.key,
    required this.label,
    required this.onTap,
    this.horizontal = false,
  });

  final String label;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  State<PlaceholderSlotWidget> createState() => _PlaceholderSlotWidgetState();
}

class _PlaceholderSlotWidgetState extends State<PlaceholderSlotWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color line = _hovered
        ? AppColors.sunGold
        : AppColors.textTertiary.withValues(alpha: 0.7);
    final TextStyle? labelStyle = text.bodySmall?.copyWith(
      color: _hovered ? AppColors.sunGold : AppColors.textTertiary,
      fontWeight: FontWeight.w600,
    );

    final Widget plus = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: line.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.add, color: line, size: 22),
    );

    final Widget content = widget.horizontal
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: <Widget>[
                plus,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(widget.label, style: labelStyle),
                ),
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              plus,
              const SizedBox(height: AppSpacing.sm),
              Text(widget.label, textAlign: TextAlign.center, style: labelStyle),
            ],
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: line,
            radius: AppSpacing.radiusMd,
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// A small circular chevron that collapses / expands a person's ancestors.
class CollapseToggleWidget extends StatelessWidget {
  const CollapseToggleWidget({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Icon(
            collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded rectangle that fills the available size.
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;
  static const double dash = 6;
  static const double gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

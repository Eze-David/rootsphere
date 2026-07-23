import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// A small floating column of zoom in/out (+ optional third) buttons, used
/// wherever a canvas/image supports pinch-zoom but should also offer an
/// explicit, discoverable control for it (the tree canvas, the fullscreen
/// image viewer).
class ZoomControls extends StatelessWidget {
  const ZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.thirdIcon,
    this.thirdTooltip,
    this.onThird,
    this.direction = Axis.vertical,
    this.bare = false,
    this.iconColor,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  /// An optional third action alongside the zoom buttons (e.g. "Recenter" on
  /// the tree canvas, "Reset zoom" on the image viewer). All three of
  /// [thirdIcon], [thirdTooltip] and [onThird] must be given together, or
  /// none at all.
  final IconData? thirdIcon;
  final String? thirdTooltip;
  final VoidCallback? onThird;

  /// [Axis.vertical] (default) stacks the buttons top-to-bottom, for a
  /// corner-docked cluster; [Axis.horizontal] lays them out side-by-side,
  /// for placement in a toolbar row.
  final Axis direction;

  /// When true, renders as plain icon buttons with no card background,
  /// shadow, or dividers — for placement directly over a backdrop that
  /// already has its own controls in that bare style (e.g. next to the
  /// fullscreen image viewer's close button). Default (false) is the
  /// self-contained floating card, for docking over a canvas with nothing
  /// else nearby to match.
  final bool bare;

  /// Icon color when [bare] is true. Defaults to white, since the only
  /// current bare usage is over a black backdrop.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bool horizontal = direction == Axis.horizontal;
    final Widget divider = horizontal
        ? const VerticalDivider(width: 1)
        : const Divider(height: 1);
    final Color? color = bare ? (iconColor ?? Colors.white) : null;
    final List<Widget> buttons = <Widget>[
      IconButton(
        tooltip: 'Zoom in',
        icon: Icon(Icons.add, color: color),
        onPressed: onZoomIn,
      ),
      if (!bare) divider,
      IconButton(
        tooltip: 'Zoom out',
        icon: Icon(Icons.remove, color: color),
        onPressed: onZoomOut,
      ),
      if (thirdIcon != null && onThird != null) ...<Widget>[
        if (!bare) divider,
        IconButton(
          tooltip: thirdTooltip,
          icon: Icon(thirdIcon, color: color),
          onPressed: onThird,
        ),
      ],
    ];
    final Widget layout = horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: buttons)
        : Column(mainAxisSize: MainAxisSize.min, children: buttons);
    if (bare) return layout;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: layout,
    );
  }
}

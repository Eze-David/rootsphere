import 'package:flutter/material.dart';

import 'adaptive_image.dart';
import 'zoom_controls.dart';

/// Opens [reference] (a network URL or local file path, same as
/// [AdaptiveImage] accepts) in a full-screen, pinch-to-zoom viewer over a
/// black backdrop, with explicit zoom buttons alongside the pinch gesture.
/// Tap the image while at the default zoom level, the close button, or swipe
/// back to dismiss.
Future<void> showFullscreenImage(BuildContext context, String reference) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullscreenImageViewer(reference: reference);
      },
    ),
  );
}

class _FullscreenImageViewer extends StatefulWidget {
  const _FullscreenImageViewer({required this.reference});
  final String reference;

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  static const double _minScale = 1;
  static const double _maxScale = 5;

  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _currentScale => _controller.value.getMaxScaleOnAxis();

  void _zoomBy(double factor) {
    final double next = (_currentScale * factor).clamp(_minScale, _maxScale);
    setState(() {
      _controller.value = Matrix4.identity()
        ..scaleByDouble(next, next, next, 1.0);
    });
  }

  void _resetZoom() {
    setState(() => _controller.value = Matrix4.identity());
  }

  void _handleTap() {
    // Dismiss only when not zoomed in — otherwise a tap while inspecting a
    // zoomed image would close the viewer instead of just, say, panning.
    if (_currentScale <= _minScale + 0.01) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTap: _handleTap,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: _minScale,
                maxScale: _maxScale,
                child: Center(
                  child: AdaptiveImage(
                    reference: widget.reference,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 8,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ZoomControls(
                  direction: Axis.horizontal,
                  bare: true,
                  onZoomIn: () => _zoomBy(1.5),
                  onZoomOut: () => _zoomBy(1 / 1.5),
                  thirdIcon: Icons.center_focus_strong_outlined,
                  thirdTooltip: 'Reset zoom',
                  onThird: _resetZoom,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

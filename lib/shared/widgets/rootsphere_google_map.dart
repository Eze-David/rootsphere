import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// One pin on a [RootsphereGoogleMap].
class MapPin {
  const MapPin({
    required this.id,
    required this.position,
    required this.title,
    this.snippet,
    this.highlighted = false,
    this.onTap,
  });

  final String id;
  final LatLng position;

  /// Shown in the pin's info window, e.g. "Enugu, Nigeria".
  final String title;

  /// Second info-window line, e.g. "3 people — tap to see who".
  final String? snippet;

  /// Drawn in a distinct colour (e.g. the person whose profile you came from).
  final bool highlighted;

  /// Tapping the info window (the pin itself just opens the info window,
  /// which is the standard Google Maps interaction).
  final VoidCallback? onTap;
}

/// Google Maps (Maps SDK for iOS/Android, Maps JavaScript API on web) with
/// RootSphere's pin colours and a dark style that follows the app theme.
/// The API key lives in the platform setup (AppDelegate.swift,
/// AndroidManifest.xml, web/index.html), not here.
class RootsphereGoogleMap extends StatefulWidget {
  const RootsphereGoogleMap({
    super.key,
    required this.pins,
    this.focus,
    this.zoom = 12,
    this.interactive = true,
  });

  final List<MapPin> pins;

  /// Centre on this point at [zoom]. When null and there are several pins,
  /// the camera fits all of them.
  final LatLng? focus;
  final double zoom;

  /// False for small preview maps that shouldn't pan/zoom (the parent
  /// handles taps instead).
  final bool interactive;

  @override
  State<RootsphereGoogleMap> createState() => _RootsphereGoogleMapState();
}

class _RootsphereGoogleMapState extends State<RootsphereGoogleMap> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  // RootSphere's warm brown/gold palette as marker hues.
  static const double _pinHue = 25; // amber-brown
  static const double _highlightHue = BitmapDescriptor.hueRed;

  LatLng get _initialTarget {
    if (widget.focus != null) return widget.focus!;
    if (widget.pins.isNotEmpty) return widget.pins.first.position;
    return const LatLng(9.08, 8.68); // Nigeria
  }

  double get _initialZoom {
    if (widget.focus != null || widget.pins.length <= 1) return widget.zoom;
    return 4;
  }

  Future<void> _onCreated(GoogleMapController controller) async {
    if (!_controller.isCompleted) _controller.complete(controller);
    if (widget.focus != null || widget.pins.length < 2) return;
    // Fit every pin on screen once the map has a size.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    double south = 90, north = -90, west = 180, east = -180;
    for (final MapPin p in widget.pins) {
      south = math.min(south, p.position.latitude);
      north = math.max(north, p.position.latitude);
      west = math.min(west, p.position.longitude);
      east = math.max(east, p.position.longitude);
    }
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          64,
        ),
      );
    } catch (_) {
      // Map not laid out yet (rare) — the initial camera is still sensible.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Set<Marker> markers = <Marker>{
      for (final MapPin p in widget.pins)
        Marker(
          markerId: MarkerId(p.id),
          position: p.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            p.highlighted ? _highlightHue : _pinHue,
          ),
          zIndexInt: p.highlighted ? 1 : 0,
          infoWindow: widget.interactive
              ? InfoWindow(title: p.title, snippet: p.snippet, onTap: p.onTap)
              : InfoWindow.noText,
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _initialTarget,
        zoom: _initialZoom,
      ),
      markers: markers,
      onMapCreated: _onCreated,
      style: dark ? _darkStyle : null,
      mapToolbarEnabled: widget.interactive && !kIsWeb,
      zoomControlsEnabled: widget.interactive && kIsWeb,
      myLocationButtonEnabled: false,
      compassEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: widget.interactive,
      // Android: a static bitmap for small previews (cheaper, no gestures).
      liteModeEnabled: !widget.interactive && !kIsWeb && _isAndroid(context),
    );
  }

  static bool _isAndroid(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.android;
}

/// Google's standard "Night" map style, so the map matches dark mode.
const String _darkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},
  {"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#17263c"}]}
]
''';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/geocoding_service.dart';
import '../../domain/entities/person.dart';
import '../providers/tree_providers.dart';
import '../widgets/osm_attribution.dart';

/// Full-screen map of everyone in the tree who has a resolvable location —
/// opened by tapping the location map card on a person's profile. People who
/// share the same place name (e.g. many relatives from "Enugu, Nigeria") are
/// grouped under one pin.
class TreeMapScreen extends ConsumerWidget {
  const TreeMapScreen({super.key, this.focusPersonId});

  /// The person whose profile this was opened from — used to centre the map
  /// and highlight their pin. Null shows the whole tree with no particular
  /// focus.
  final String? focusPersonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Person> persons = ref.watch(personsProvider).value ?? const <Person>[];

    final Map<String, List<Person>> byLocation = <String, List<Person>>{};
    for (final p in persons) {
      final String loc = p.location;
      if (loc.isEmpty) continue;
      byLocation.putIfAbsent(loc, () => <Person>[]).add(p);
    }

    final List<_LocationGroup> groups = <_LocationGroup>[];
    for (final entry in byLocation.entries) {
      final GeocodeResult? result = ref.watch(geocodeProvider(entry.key)).value;
      if (result == null) continue;
      groups.add(_LocationGroup(
        location: entry.key,
        people: entry.value,
        point: LatLng(result.lat, result.lon),
      ));
    }

    _LocationGroup? focusGroup;
    if (focusPersonId != null) {
      for (final g in groups) {
        if (g.people.any((p) => p.id == focusPersonId)) {
          focusGroup = g;
          break;
        }
      }
    }

    final bool loading = byLocation.isNotEmpty && groups.isEmpty &&
        byLocation.keys.any((k) => ref.watch(geocodeProvider(k)).isLoading);
    final LatLng centre = focusGroup?.point ??
        (groups.isNotEmpty ? groups.first.point : const LatLng(20, 0));
    final double zoom = focusGroup != null ? 12 : (groups.length > 1 ? 3 : 12);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Map'),
        actions: <Widget>[
          if (focusGroup != null)
            IconButton(
              tooltip: 'Open in Maps',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _openExternally(focusGroup!.point),
            ),
        ],
      ),
      body: groups.isEmpty
          ? Center(
              child: Text(
                loading ? 'Locating people…' : 'No locations to show yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          // flutter_map computes tile ranges from the widget's own render
          // size. Two bad cases produce Infinity/NaN in that math and crash:
          // unbounded constraints (size infinite) and — per flutter_map's own
          // `kImpossibleSize` handling — a genuine 0×0 size, which happens
          // when the native platform resolution isn't available yet on the
          // very first frame(s) of a cold/restored launch straight into this
          // screen. `isFinite` alone doesn't catch the zero case (0.0 *is*
          // finite), so both are checked explicitly.
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool sizeReady = constraints.maxWidth.isFinite &&
                    constraints.maxHeight.isFinite &&
                    constraints.maxWidth > 0 &&
                    constraints.maxHeight > 0;
                if (!sizeReady) {
                  return const SizedBox.shrink();
                }
                return FlutterMap(
                  options: MapOptions(
                    initialCenter: centre,
                    initialZoom: zoom,
                    minZoom: 2,
                    maxZoom: 18,
                  ),
                  children: <Widget>[
                    TileLayer(
                      // The raw OSM tile server is only meant for light/testing
                      // traffic and throttles real interactive use (panning
                      // fast can queue up more tile requests than it'll serve,
                      // which is what was making the map "get stuck" / run out
                      // of memory). CARTO's free Voyager tiles are a CDN
                      // that's actually meant for app traffic — no API key.
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      subdomains: const <String>['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.rootsphere.app',
                      // The default fade-in restarts an AnimationController
                      // whenever a tile image resolves — including
                      // synchronously from cache, which happens mid-build and
                      // throws "setState() called during build". Tiles
                      // appearing instantly is an acceptable trade-off here.
                      tileDisplay: const TileDisplay.instantaneous(),
                    ),
                    MarkerLayer(markers: <Marker>[
                      for (final g in groups)
                        Marker(
                          point: g.point,
                          width: 60,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: _Pin(
                            group: g,
                            highlighted: identical(g, focusGroup),
                            onTap: () => _onPinTap(context, g),
                          ),
                        ),
                    ]),
                    const OsmAttribution(),
                  ],
                );
              },
            ),
    );
  }

  void _onPinTap(BuildContext context, _LocationGroup g) {
    if (g.people.length == 1) {
      context.push('${AppRoutes.person}/${g.people.first.id}');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(g.location, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final p in g.people)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(p.fullName),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('${AppRoutes.person}/${p.id}');
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternally(LatLng point) async {
    final Uri uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}'
      '#map=15/${point.latitude}/${point.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _LocationGroup {
  _LocationGroup({required this.location, required this.people, required this.point});
  final String location;
  final List<Person> people;
  final LatLng point;
}

class _Pin extends StatefulWidget {
  const _Pin({required this.group, required this.highlighted, required this.onTap});
  final _LocationGroup group;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_Pin> createState() => _PinState();
}

class _PinState extends State<_Pin> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Same hover treatment as the tree's cards/placeholder slots and the
    // opportunities map: sunGold wins over the plain focus-person highlight.
    final Color color = _hovered
        ? AppColors.sunGold
        : widget.highlighted
            ? AppColors.primary
            : AppColors.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.group.people.length > 1)
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  '${widget.group.people.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            Icon(Icons.location_on, color: color, size: _hovered ? 40 : 36),
          ],
        ),
      ),
    );
  }
}

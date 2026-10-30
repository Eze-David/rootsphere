import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/geocoding_service.dart';
import '../../domain/entities/person.dart';
import '../providers/tree_providers.dart';
import '../../../../shared/widgets/rootsphere_google_map.dart';

/// Full-screen map of everyone in the tree who has a resolvable location —
/// opened by tapping the location map card on a person's profile. People who
/// share the same place name (e.g. many relatives from "Enugu, Nigeria") are
/// grouped under one pin. Rendered with Google Maps.
class TreeMapScreen extends ConsumerWidget {
  const TreeMapScreen({super.key, this.focusPersonId});

  /// The person whose profile this was opened from — used to centre the map
  /// and highlight their pin. Null shows the whole tree with no particular
  /// focus.
  final String? focusPersonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Person> persons =
        ref.watch(personsProvider).value ?? const <Person>[];

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
      groups.add(
        _LocationGroup(
          location: entry.key,
          people: entry.value,
          point: LatLng(result.lat, result.lon),
        ),
      );
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

    final bool loading =
        byLocation.isNotEmpty &&
        groups.isEmpty &&
        byLocation.keys.any((k) => ref.watch(geocodeProvider(k)).isLoading);

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
          : RootsphereGoogleMap(
              focus: focusGroup?.point,
              pins: <MapPin>[
                for (final g in groups)
                  MapPin(
                    id: g.location,
                    position: g.point,
                    title: g.location,
                    snippet: g.people.length == 1
                        ? '${g.people.first.fullName} — tap to open'
                        : '${g.people.length} people — tap to see who',
                    highlighted: identical(g, focusGroup),
                    onTap: () => _onPinTap(context, g),
                  ),
              ],
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
              child: Text(
                g.location,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
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
    final Uri uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${point.latitude},${point.longitude}',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _LocationGroup {
  _LocationGroup({
    required this.location,
    required this.people,
    required this.point,
  });
  final String location;
  final List<Person> people;
  final LatLng point;
}

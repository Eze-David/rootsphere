import 'package:flutter/material.dart';

/// Minimal map attribution — credits both OpenStreetMap (the underlying map
/// data) and CARTO (which hosts/renders the tiles we actually fetch), as
/// required by their respective terms — without flutter_map's own
/// self-promotion text baked into its [SimpleAttributionWidget].
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
        child: Text(
          '© OpenStreetMap contributors © CARTO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
        ),
      ),
    );
  }
}

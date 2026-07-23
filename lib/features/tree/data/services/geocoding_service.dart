import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

/// A resolved location, in coordinates suitable for plotting a map pin.
class GeocodeResult {
  const GeocodeResult({required this.lat, required this.lon, this.displayName});

  final double lat;
  final double lon;
  final String? displayName;
}

/// Resolves a free-text place name to coordinates via the `geocode` Supabase
/// Edge Function (OpenStreetMap Nominatim, cached server-side).
///
/// `null` means "genuinely no coordinates for this place" (Supabase isn't
/// configured, empty query, or the place wasn't found) — a result the caller
/// can safely treat as permanent and fall back to a pin-less placeholder for.
/// Anything else (network failure, function unreachable, non-200 status)
/// *throws* instead of returning null, so [geocodeProvider]'s `autoDispose`
/// lets a revisit retry rather than caching a transient failure as if the
/// place didn't exist — that mismatch was why pins would randomly go missing
/// on some devices/networks and never come back for the rest of the session.
class GeocodingService {
  GeocodingService();

  Future<GeocodeResult?> geocode(String query) async {
    if (!SupabaseConfig.isReady || query.trim().isEmpty) return null;
    final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
      'geocode',
      body: <String, dynamic>{'query': query},
    );
    if (res.status != 200) {
      throw GeocodingFailure('Geocoding failed (status ${res.status})');
    }
    final dynamic data = res.data;
    if (data is! Map || data['available'] != true) return null;
    final num? lat = data['lat'] as num?;
    final num? lon = data['lon'] as num?;
    if (lat == null || lon == null) return null;
    return GeocodeResult(
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      displayName: data['displayName']?.toString(),
    );
  }
}

/// Thrown for transient geocoding failures (network, function unreachable,
/// non-200 status) — distinct from a `null` result, which means the place
/// was looked up successfully and just has no coordinates.
class GeocodingFailure implements Exception {
  GeocodingFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

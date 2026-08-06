import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/global_person_match.dart';
import '../../domain/entities/historical_record.dart';

/// Searches for people across ALL trees (including those the user isn't a
/// member of) via the `search_persons_global` SECURITY DEFINER RPC, which
/// returns a privacy-safe projection. Powers cross-tree discovery on the
/// records search screen.
///
/// Returns an empty list when Supabase isn't configured (local/offline mode has
/// no global database to search).
class GlobalPeopleService {
  GlobalPeopleService();

  Future<List<GlobalPersonMatch>> search(RecordSearchQuery query) async {
    if (!SupabaseConfig.isReady) return const <GlobalPersonMatch>[];
    try {
      final dynamic data = await SupabaseConfig.client.rpc(
        'search_persons_global',
        params: <String, dynamic>{
          'p_first': query.firstName.trim(),
          'p_last': query.lastName.trim(),
          'p_place': query.place.trim(),
          'p_year': query.year,
        },
      );
      final List<dynamic> rows = data as List<dynamic>? ?? const <dynamic>[];
      return rows
          .map(
            (e) =>
                GlobalPersonMatch.fromRow(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } on PostgrestException {
      return const <GlobalPersonMatch>[];
    } catch (_) {
      return const <GlobalPersonMatch>[];
    }
  }

  /// Free-text variant for a single search box (e.g. the main records
  /// library) that has one term rather than separate first/last/place
  /// fields — matches if [query] shows up in any of a person's name or
  /// place fields, via `search_persons_global_freetext`, instead of
  /// requiring every structured field to match at once.
  Future<List<GlobalPersonMatch>> searchFreeText(
    String query, {
    int? year,
  }) async {
    if (!SupabaseConfig.isReady) return const <GlobalPersonMatch>[];
    try {
      final dynamic data = await SupabaseConfig.client.rpc(
        'search_persons_global_freetext',
        params: <String, dynamic>{'p_query': query.trim(), 'p_year': year},
      );
      final List<dynamic> rows = data as List<dynamic>? ?? const <dynamic>[];
      return rows
          .map(
            (e) =>
                GlobalPersonMatch.fromRow(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } on PostgrestException {
      return const <GlobalPersonMatch>[];
    } catch (_) {
      return const <GlobalPersonMatch>[];
    }
  }
}

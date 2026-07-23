import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/global_record_match.dart';
import '../../domain/entities/historical_record.dart';

/// Searches for unattached records across ALL trees (not just the user's own)
/// via the `search_records_global` SECURITY DEFINER RPC, which returns a
/// privacy-safe projection of records nobody has linked to a person — a
/// community contribution any signed-in user can find, regardless of whether
/// they have a tree of their own.
///
/// Returns an empty list when Supabase isn't configured (local/offline mode has
/// no global database to search).
class GlobalRecordsService {
  GlobalRecordsService();

  Future<List<GlobalRecordMatch>> search(RecordSearchQuery query) async {
    if (!SupabaseConfig.isReady) return const <GlobalRecordMatch>[];
    final String freeText = <String>[
      query.firstName.trim(),
      query.lastName.trim(),
      query.place.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    try {
      final dynamic data = await SupabaseConfig.client.rpc(
        'search_records_global',
        params: <String, dynamic>{
          'p_query': freeText,
          'p_type': query.type?.name,
          'p_year': query.year,
        },
      );
      final List<dynamic> rows = data as List<dynamic>? ?? const <dynamic>[];
      return rows
          .map(
            (e) =>
                GlobalRecordMatch.fromRow(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } on PostgrestException {
      return const <GlobalRecordMatch>[];
    } catch (_) {
      return const <GlobalRecordMatch>[];
    }
  }
}

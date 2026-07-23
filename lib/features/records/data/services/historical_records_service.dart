import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/historical_record.dart';

/// Searches an external genealogy provider (FamilySearch) for historical
/// records via the Supabase Edge Function `records-search`.
///
/// The provider credentials live only in the edge function (brief: "keys never
/// on client"). This service is a thin, provider-agnostic client over the
/// normalised JSON the function returns. It degrades gracefully: when Supabase
/// isn't configured or the function isn't deployed, [search] returns an
/// unavailable result instead of throwing.
class HistoricalRecordsService {
  HistoricalRecordsService();

  Future<RecordSearchResult> search(RecordSearchQuery query) async {
    if (!SupabaseConfig.isReady) {
      return const RecordSearchResult(
        available: false,
        message: 'Connect Supabase to search historical records.',
      );
    }
    try {
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'records-search',
        body: query.toJson(),
      );
      if (res.status != 200) {
        return RecordSearchResult(
          available: false,
          message: 'Search service returned ${res.status}.',
        );
      }
      final dynamic data = res.data;
      final List<dynamic> rows = data is Map<String, dynamic>
          ? (data['records'] as List<dynamic>? ?? const <dynamic>[])
          : (data as List<dynamic>? ?? const <dynamic>[]);
      final records = rows
          .map(
            (e) =>
                HistoricalRecord.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      return RecordSearchResult(records: records);
    } on FunctionException catch (e) {
      return RecordSearchResult(
        available: false,
        message: 'Search unavailable (${e.status}).',
      );
    } catch (_) {
      return const RecordSearchResult(
        available: false,
        message: 'Could not reach the search service.',
      );
    }
  }
}

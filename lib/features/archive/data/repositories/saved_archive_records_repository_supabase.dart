import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/repositories/saved_archive_records_repository.dart';

class SavedArchiveRecordsRepositorySupabase
    implements SavedArchiveRecordsRepository {
  SavedArchiveRecordsRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('saved_archive_records');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Stream<Set<String>> watchSavedIds() {
    if (_uid.isEmpty) return Stream<Set<String>>.value(const <String>{});
    return _table
        .stream(primaryKey: <String>['user_id', 'record_id'])
        .eq('user_id', _uid)
        .map((rows) => rows.map((r) => r['record_id'] as String).toSet());
  }

  @override
  Future<void> save(String recordId) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      await _table.upsert(<String, dynamic>{
        'user_id': _uid,
        'record_id': recordId,
      });
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> unsave(String recordId) async {
    try {
      await _table.delete().eq('user_id', _uid).eq('record_id', recordId);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}

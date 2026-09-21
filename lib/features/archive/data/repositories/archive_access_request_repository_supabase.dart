import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/archive_access_request.dart';
import '../../domain/repositories/archive_access_request_repository.dart';

class ArchiveAccessRequestRepositorySupabase
    implements ArchiveAccessRequestRepository {
  ArchiveAccessRequestRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('archive_access_requests');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Stream<List<ArchiveAccessRequest>> watchMine() {
    if (_uid.isEmpty) return Stream<List<ArchiveAccessRequest>>.value(const []);
    return _table
        .stream(primaryKey: <String>['id'])
        .eq('user_id', _uid)
        .map((rows) => rows.map(ArchiveAccessRequest.fromJson).toList());
  }

  @override
  Stream<ArchiveAccessRequest?> watchForRecord(String recordId) {
    return watchMine().map((requests) {
      for (final r in requests) {
        if (r.recordId == recordId) return r;
      }
      return null;
    });
  }

  @override
  Future<void> request(String recordId, {String? note}) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      await _table.upsert(<String, dynamic>{
        'record_id': recordId,
        'user_id': _uid,
        'status': 'pending',
        'note': note,
        'reviewed_at': null,
        'reviewed_by': null,
      }, onConflict: 'record_id,user_id');
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Stream<List<ArchiveAccessRequest>> watchPending() {
    return _table
        .stream(primaryKey: <String>['id'])
        .eq('status', 'pending')
        .order('created_at')
        .map((rows) => rows.map(ArchiveAccessRequest.fromJson).toList());
  }

  @override
  Future<void> review(String id, {required bool approve}) async {
    try {
      await _table
          .update(<String, dynamic>{
            'status': approve ? 'approved' : 'rejected',
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': _uid,
          })
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}

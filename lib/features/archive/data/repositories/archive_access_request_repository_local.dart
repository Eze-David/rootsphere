import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/archive_access_request.dart';
import '../../domain/repositories/archive_access_request_repository.dart';

/// SharedPreferences-backed [ArchiveAccessRequestRepository] used when
/// Supabase is not configured (single-device demo mode).
class ArchiveAccessRequestRepositoryLocal
    implements ArchiveAccessRequestRepository {
  ArchiveAccessRequestRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;
  final StreamController<List<ArchiveAccessRequest>> _controller =
      StreamController<List<ArchiveAccessRequest>>.broadcast();

  static const String _key = 'archive_access_requests_v1';
  static const String _demoUserId = 'local_demo_user';

  List<Map<String, dynamic>> _readRaw() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<ArchiveAccessRequest> _read() =>
      _readRaw().map(ArchiveAccessRequest.fromJson).toList();

  Future<void> _write(List<Map<String, dynamic>> raw) async {
    await _prefs.setString(_key, jsonEncode(raw));
    _controller.add(raw.map(ArchiveAccessRequest.fromJson).toList());
  }

  @override
  Stream<List<ArchiveAccessRequest>> watchMine() {
    scheduleMicrotask(() => _controller.add(_read()));
    return _controller.stream.map(
      (list) => list.where((r) => r.userId == _demoUserId).toList(),
    );
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
    final List<Map<String, dynamic>> raw = _readRaw();
    final int idx = raw.indexWhere(
      (r) => r['record_id'] == recordId && r['user_id'] == _demoUserId,
    );
    final Map<String, dynamic> row = <String, dynamic>{
      'id': idx >= 0 ? raw[idx]['id'] : 'req_${DateTime.now().microsecondsSinceEpoch}',
      'record_id': recordId,
      'user_id': _demoUserId,
      'status': 'pending',
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      'reviewed_at': null,
      'reviewed_by': null,
    };
    if (idx >= 0) {
      raw[idx] = row;
    } else {
      raw.add(row);
    }
    await _write(raw);
  }

  @override
  Stream<List<ArchiveAccessRequest>> watchPending() {
    scheduleMicrotask(() => _controller.add(_read()));
    return _controller.stream.map(
      (list) => list
          .where((r) => r.status == ArchiveAccessRequestStatus.pending)
          .toList(),
    );
  }

  @override
  Future<void> review(String id, {required bool approve}) async {
    final List<Map<String, dynamic>> raw = _readRaw();
    final int idx = raw.indexWhere((r) => r['id'] == id);
    if (idx < 0) return;
    raw[idx] = <String, dynamic>{
      ...raw[idx],
      'status': approve ? 'approved' : 'rejected',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': _demoUserId,
    };
    await _write(raw);
  }
}

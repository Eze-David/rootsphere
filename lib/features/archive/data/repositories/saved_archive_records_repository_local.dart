import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/saved_archive_records_repository.dart';

/// SharedPreferences-backed [SavedArchiveRecordsRepository] used when
/// Supabase is not configured (single-device demo mode).
class SavedArchiveRecordsRepositoryLocal
    implements SavedArchiveRecordsRepository {
  SavedArchiveRecordsRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  static const String _key = 'saved_archive_records_v1';

  Set<String> _read() {
    final List<String>? raw = _prefs.getStringList(_key);
    return raw?.toSet() ?? <String>{};
  }

  Future<void> _write(Set<String> ids) async {
    await _prefs.setStringList(_key, ids.toList());
    _controller.add(ids);
  }

  @override
  Stream<Set<String>> watchSavedIds() {
    scheduleMicrotask(() => _controller.add(_read()));
    return _controller.stream;
  }

  @override
  Future<void> save(String recordId) async {
    await _write(_read()..add(recordId));
  }

  @override
  Future<void> unsave(String recordId) async {
    await _write(_read()..remove(recordId));
  }
}

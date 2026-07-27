import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/record.dart';
import '../../domain/repositories/record_repository.dart';

/// SharedPreferences-backed [RecordRepository] used when Supabase is not
/// configured. Records are stored as a JSON list keyed by tree id; a broadcast
/// stream per tree lets the UI react to mutations. The demo "okonkwo" tree is
/// seeded once to match the Records library mockup.
class RecordRepositoryLocal implements RecordRepository {
  RecordRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;

  final Map<String, StreamController<List<Record>>> _controllers =
      <String, StreamController<List<Record>>>{};

  static const String _seededFlag = 'records_seeded_v1';

  String _key(String treeId) => 'tree_records_$treeId';

  List<Record> _read(String treeId) {
    final String? raw = _prefs.getString(_key(treeId));
    if (raw == null || raw.isEmpty) return <Record>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final records = list
          .map((e) => Record.fromJson(e as Map<String, dynamic>))
          .toList();
      _sort(records);
      return records;
    } catch (_) {
      return <Record>[];
    }
  }

  Future<void> _write(String treeId, List<Record> records) async {
    _sort(records);
    await _prefs.setString(
      _key(treeId),
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
    _controllers[treeId]?.add(records);
  }

  void _sort(List<Record> records) {
    records.sort((a, b) {
      final DateTime ad = a.createdAt ?? DateTime(0);
      final DateTime bd = b.createdAt ?? DateTime(0);
      return bd.compareTo(ad);
    });
  }

  @override
  Stream<List<Record>> watchRecords(String treeId) {
    _maybeSeed(treeId);
    final controller = _controllers.putIfAbsent(
      treeId,
      () => StreamController<List<Record>>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(_read(treeId)));
    return controller.stream;
  }

  @override
  Future<List<Record>> getRecords(String treeId) async {
    _maybeSeed(treeId);
    return _read(treeId);
  }

  @override
  Stream<List<Record>> watchAllRecords() {
    // No real cross-user roles offline (single-device demo mode) — "all
    // records" just merges every tree already stored locally.
    _maybeSeed('okonkwo');
    final controller = StreamController<List<Record>>.broadcast();
    scheduleMicrotask(() => controller.add(_readAll()));
    return controller.stream;
  }

  List<Record> _readAll() {
    final List<Record> all = <Record>[
      for (final String key in _prefs.getKeys())
        if (key.startsWith('tree_records_'))
          ..._read(key.substring('tree_records_'.length)),
    ];
    _sort(all);
    return all;
  }

  @override
  Future<void> upsertRecord(Record record) async {
    final List<Record> records = _read(record.treeId);
    final int idx = records.indexWhere((r) => r.id == record.id);
    if (idx >= 0) {
      records[idx] = record;
    } else {
      records.add(record);
    }
    await _write(record.treeId, records);
  }

  @override
  Future<void> deleteRecord(String treeId, String id) async {
    final List<Record> records = _read(treeId)..removeWhere((r) => r.id == id);
    await _write(treeId, records);
  }

  // ── Seed ───────────────────────────────────────────────────────────────────

  /// Seeds the demo "Okonkwo" records from the mockup on first launch.
  void _maybeSeed(String treeId) {
    if (treeId != 'okonkwo') return;
    if (_prefs.getBool(_seededFlag) == true) return;
    if (_read(treeId).isNotEmpty) return;

    DateTime y(int year) => DateTime(year, 1, 1);
    const String tree = 'okonkwo';

    final List<Record> seed = <Record>[
      Record(
        id: 'rec_birth_adaeze',
        treeId: tree,
        type: RecordType.birth,
        title: 'Adaeze Okonkwo',
        repository: 'Lagos State Registry',
        date: y(1986),
        createdAt: y(1986),
      ),
      Record(
        id: 'rec_marriage_emeka_ngozi',
        treeId: tree,
        type: RecordType.marriage,
        title: 'Emeka & Ngozi',
        repository: 'Enugu Registry',
        date: y(1978),
        createdAt: y(1978),
      ),
      Record(
        id: 'rec_census_okonkwo',
        treeId: tree,
        type: RecordType.census,
        title: 'Okonkwo household',
        repository: 'National Archives',
        date: y(1963),
        createdAt: y(1963),
      ),
      Record(
        id: 'rec_military_arthur',
        treeId: tree,
        type: RecordType.military,
        title: 'Arthur Okonkwo',
        repository: 'Nigeria Army Records',
        date: y(1941),
        createdAt: y(1941),
      ),
    ];

    _prefs.setString(
      _key(tree),
      jsonEncode(seed.map((r) => r.toJson()).toList()),
    );
    _prefs.setBool(_seededFlag, true);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/archive_record.dart';
import '../../domain/repositories/archive_repository.dart';

/// SharedPreferences-backed [ArchiveRepository] used when Supabase is not
/// configured (single-device demo mode — every "admin" on this device shares
/// the same local list, there's no real RLS to emulate offline).
class ArchiveRepositoryLocal implements ArchiveRepository {
  ArchiveRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;
  final StreamController<List<ArchiveRecord>> _controller =
      StreamController<List<ArchiveRecord>>.broadcast();

  static const String _key = 'archive_records_v1';
  int _seq = 0;

  List<ArchiveRecord> _read() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <ArchiveRecord>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final records = list
          .map((e) => ArchiveRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _sort(records);
      return records;
    } catch (_) {
      return <ArchiveRecord>[];
    }
  }

  Future<void> _write(List<ArchiveRecord> records) async {
    _sort(records);
    await _prefs.setString(
      _key,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
    _controller.add(records);
  }

  void _sort(List<ArchiveRecord> records) {
    records.sort((a, b) {
      final DateTime ad = a.createdAt ?? DateTime(0);
      final DateTime bd = b.createdAt ?? DateTime(0);
      return bd.compareTo(ad);
    });
  }

  @override
  Stream<List<ArchiveRecord>> watchAll() {
    scheduleMicrotask(() => _controller.add(_read()));
    return _controller.stream;
  }

  @override
  Future<void> upsertRecord(ArchiveRecord record) async {
    final List<ArchiveRecord> records = _read();
    final int idx = records.indexWhere((r) => r.id == record.id);
    final ArchiveRecord toSave = record.createdAt == null
        ? record.copyWith(createdAt: DateTime.now())
        : record;
    if (idx >= 0) {
      records[idx] = toSave.copyWith(updatedAt: DateTime.now());
    } else {
      records.add(toSave);
    }
    await _write(records);
  }

  @override
  Future<void> submitForReview(String id) async {
    final List<ArchiveRecord> records = _read();
    final int idx = records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final ArchiveRecord existing = records[idx];
    records[idx] = existing.copyWith(
      reviewStatus: ArchiveReviewStatus.pendingReview,
      recordRef: existing.recordRef ?? _generateRef(existing),
      updatedAt: DateTime.now(),
    );
    await _write(records);
  }

  @override
  Future<void> review(String id, {required bool approved, String? note}) async {
    final List<ArchiveRecord> records = _read();
    final int idx = records.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    records[idx] = records[idx].copyWith(
      reviewStatus: approved
          ? ArchiveReviewStatus.published
          : ArchiveReviewStatus.rejected,
      // Access level (Online/Permission/Archive) is an explicit admin choice
      // on the Add record form, independent of the review decision — publish
      // doesn't override it (a rejected record just stops appearing in the
      // published catalogue, since that's filtered by reviewStatus).
      reviewerNote: note,
      reviewedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _write(records);
  }

  @override
  Future<void> deleteRecord(String id) async {
    final List<ArchiveRecord> records = _read()..removeWhere((r) => r.id == id);
    await _write(records);
  }

  String _generateRef(ArchiveRecord r) {
    _seq += 1;
    String code(String s) {
      final String letters = s.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
      if (letters.isEmpty) return 'GEN';
      final String head = letters.length >= 3 ? letters.substring(0, 3) : letters;
      return head.padRight(3, 'X');
    }

    final String seqStr = _seq.toString().padLeft(6, '0');
    return 'RS-${code(r.country)}-${code(r.stateRegion)}-${code(r.type.name)}-$seqStr';
  }
}

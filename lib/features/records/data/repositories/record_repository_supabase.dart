import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/record.dart';
import '../../domain/repositories/record_repository.dart';

/// Supabase-backed [RecordRepository].
///
/// Records live in a `records` table whose shape mirrors the [Record] model
/// (person links as a text[] array). Member-based RLS (see migration
/// 20260617000000_tree_members.sql) lets every tree member read/write its
/// records. Live updates use Supabase Realtime via `.stream()`.
class RecordRepositorySupabase implements RecordRepository {
  RecordRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _records => _client.from('records');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Stream<List<Record>> watchRecords(String treeId) {
    return _records
        .stream(primaryKey: <String>['id'])
        .eq('tree_id', treeId)
        .order('created_at')
        .map((rows) {
          final records = rows.map(_fromRow).toList();
          records.sort((a, b) {
            final DateTime ad = a.createdAt ?? DateTime(0);
            final DateTime bd = b.createdAt ?? DateTime(0);
            return bd.compareTo(ad);
          });
          return records;
        });
  }

  @override
  Future<List<Record>> getRecords(String treeId) async {
    try {
      final List<Map<String, dynamic>> rows = await _records
          .select()
          .eq('tree_id', treeId)
          .order('created_at', ascending: false);
      return rows.map(_fromRow).toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> upsertRecord(Record record) async {
    try {
      await _records.upsert(_toRow(record));
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> deleteRecord(String treeId, String id) async {
    try {
      await _records.delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _toRow(Record r) => <String, dynamic>{
    'id': r.id,
    'tree_id': r.treeId,
    'owner_id': _uid,
    'type': r.type.name,
    'title': r.title,
    'repository': r.repository,
    'date': r.date?.toIso8601String(),
    'file_url': r.fileUrl,
    'file_name': r.fileName,
    'ocr_text': r.ocrText,
    'citation_override': r.citationOverride,
    'notes': r.notes,
    'person_ids': r.personIds,
    'ai_summary': r.aiSummary,
    'ai_translation': r.aiTranslation,
    'ai_translation_lang': r.aiTranslationLang,
    'ai_locations': r.aiLocations,
  };

  Record _fromRow(Map<String, dynamic> row) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return Record(
      id: row['id'] as String,
      treeId: row['tree_id'] as String,
      type: RecordType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => RecordType.other,
      ),
      title: row['title'] as String? ?? '',
      repository: row['repository'] as String? ?? '',
      date: parse(row['date']),
      fileUrl: row['file_url'] as String?,
      fileName: row['file_name'] as String?,
      ocrText: row['ocr_text'] as String?,
      citationOverride: row['citation_override'] as String?,
      notes: row['notes'] as String?,
      personIds: (row['person_ids'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      aiSummary: row['ai_summary'] as String?,
      aiTranslation: row['ai_translation'] as String?,
      aiTranslationLang: row['ai_translation_lang'] as String?,
      aiLocations: (row['ai_locations'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      createdAt: parse(row['created_at']),
    );
  }
}

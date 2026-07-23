import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/hint.dart';
import '../../domain/repositories/hint_repository.dart';

/// Supabase-backed [HintRepository].
///
/// Hints live in a `hints` table. Member-based RLS (see the tree-members
/// migration) lets every tree member read/triage its hints. Live updates use
/// Supabase Realtime via `.stream()`.
class HintRepositorySupabase implements HintRepository {
  HintRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _hints => _client.from('hints');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Stream<List<Hint>> watchHints(String treeId) {
    return _hints
        .stream(primaryKey: <String>['id'])
        .eq('tree_id', treeId)
        .map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Future<List<Hint>> getHints(String treeId) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _hints.select().eq('tree_id', treeId);
      return rows.map(_fromRow).toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> upsertHint(Hint hint) async {
    try {
      await _hints.upsert(_toRow(hint));
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> replacePendingHints(String treeId, List<Hint> hints) async {
    try {
      // Drop existing pending hints, then insert the fresh set (skipping any
      // that match an already-triaged hint by identity).
      final List<Map<String, dynamic>> existing = await _hints
          .select('type, person_id, related_person_id, record_id, field, status')
          .eq('tree_id', treeId);
      final Set<String> triagedKeys = existing
          .where((r) => (r['status'] as String?) != 'pending')
          .map(_rowDedupeKey)
          .toSet();

      await _hints.delete().eq('tree_id', treeId).eq('status', 'pending');

      final List<Map<String, dynamic>> rows = hints
          .where((h) => !triagedKeys.contains(_dedupeKey(h)))
          .map(_toRow)
          .toList();
      if (rows.isNotEmpty) await _hints.insert(rows);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> deleteHint(String treeId, String id) async {
    try {
      await _hints.delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  String _dedupeKey(Hint h) => <String>[
        h.type.name,
        h.personId ?? '',
        h.relatedPersonId ?? '',
        h.recordId ?? '',
        h.field ?? '',
      ].join('|');

  String _rowDedupeKey(Map<String, dynamic> r) => <String>[
        r['type']?.toString() ?? '',
        r['person_id']?.toString() ?? '',
        r['related_person_id']?.toString() ?? '',
        r['record_id']?.toString() ?? '',
        r['field']?.toString() ?? '',
      ].join('|');

  Map<String, dynamic> _toRow(Hint h) => <String, dynamic>{
        'id': h.id,
        'tree_id': h.treeId,
        'owner_id': _uid,
        'type': h.type.name,
        'title': h.title,
        'description': h.description,
        'confidence': h.confidence,
        'status': h.status.name,
        'source': h.source,
        'person_id': h.personId,
        'related_person_id': h.relatedPersonId,
        'record_id': h.recordId,
        'field': h.field,
        'suggested_value': h.suggestedValue,
        'relation': h.relation?.name,
      };

  Hint _fromRow(Map<String, dynamic> row) {
    return Hint(
      id: row['id'] as String,
      treeId: row['tree_id'] as String,
      type: HintType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => HintType.missingData,
      ),
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      confidence: (row['confidence'] as num?)?.round() ?? 50,
      status: HintStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => HintStatus.pending,
      ),
      source: row['source'] as String? ?? 'local',
      personId: row['person_id'] as String?,
      relatedPersonId: row['related_person_id'] as String?,
      recordId: row['record_id'] as String?,
      field: row['field'] as String?,
      suggestedValue: row['suggested_value'] as String?,
      relation: row['relation'] == null
          ? null
          : HintRelation.values.firstWhere(
              (r) => r.name == row['relation'],
              orElse: () => HintRelation.parent,
            ),
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse(row['created_at'].toString()),
    );
  }
}

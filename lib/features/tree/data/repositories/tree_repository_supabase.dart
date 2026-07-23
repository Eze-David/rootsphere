import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/edit_history_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/timeline_event.dart';
import '../../domain/repositories/tree_repository.dart';

/// Supabase-backed [TreeRepository].
///
/// Persons live in a single `persons` table whose shape mirrors the client
/// [Person] model (id arrays for relationships, JSONB for events), so this maps
/// 1:1 with the local implementation. Live updates use Supabase Realtime via
/// `.stream()`.
class TreeRepositorySupabase implements TreeRepository {
  TreeRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _persons => _client.from('persons');
  SupabaseQueryBuilder get _trees => _client.from('trees');
  SupabaseQueryBuilder get _personEdits => _client.from('person_edits');

  String get _uid => _client.auth.currentUser?.id ?? '';

  // ── Reads ────────────────────────────────────────────────────────────────

  @override
  Stream<List<Person>> watchPersons(String treeId) {
    return _persons
        .stream(primaryKey: <String>['id'])
        .eq('tree_id', treeId)
        .map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Future<List<Person>> getPersons(String treeId) async {
    try {
      final List<Map<String, dynamic>> rows = await _persons.select().eq(
        'tree_id',
        treeId,
      );
      return rows.map(_fromRow).toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  @override
  Future<void> upsertPerson(Person person) async {
    await _ensureTree(person.treeId);
    try {
      await _persons.upsert(_toRow(person));
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> deletePerson(String treeId, String id) async {
    try {
      // Scrub dangling parent/spouse references on sibling rows.
      final List<Person> all = await getPersons(treeId);
      for (final p in all) {
        if (p.parentIds.contains(id) || p.spouseIds.contains(id)) {
          await _persons
              .update(<String, dynamic>{
                'parent_ids': p.parentIds.where((x) => x != id).toList(),
                'spouse_ids': p.spouseIds.where((x) => x != id).toList(),
              })
              .eq('id', p.id);
        }
      }
      await _persons.delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> linkChild({
    required String treeId,
    required String parentId,
    required String childId,
  }) async {
    final Person? child = await _getPerson(childId);
    if (child == null) return;
    if (child.parentIds.contains(parentId)) return;
    await _persons
        .update(<String, dynamic>{
          'parent_ids': <String>[...child.parentIds, parentId],
        })
        .eq('id', childId);
  }

  @override
  Future<void> linkSpouses({
    required String treeId,
    required String aId,
    required String bId,
  }) async {
    await _addSpouse(aId, bId);
    await _addSpouse(bId, aId);
  }

  // ── Edit history ─────────────────────────────────────────────────────────

  @override
  Future<void> addEditHistory(EditHistoryEntry entry) async {
    try {
      await _personEdits.insert(<String, dynamic>{
        'id': entry.id,
        'tree_id': entry.treeId,
        'person_id': entry.personId,
        'reason': entry.reason,
        'editor_id': entry.editorId ?? (_uid.isEmpty ? null : _uid),
        'editor_name': entry.editorName,
        'changed_fields': entry.changedFields,
        'created_at': entry.createdAt.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<List<EditHistoryEntry>> getEditHistory(String personId) async {
    try {
      final List<Map<String, dynamic>> rows = await _personEdits
          .select()
          .eq('person_id', personId)
          .order('created_at', ascending: false);
      return rows.map(_editFromRow).toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<List<EditHistoryEntry>> getRecentEditHistory(
    String treeId, {
    int limit = 20,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _personEdits
          .select()
          .eq('tree_id', treeId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(_editFromRow).toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  EditHistoryEntry _editFromRow(Map<String, dynamic> row) {
    return EditHistoryEntry(
      id: row['id'] as String,
      treeId: row['tree_id'] as String,
      personId: row['person_id'] as String,
      reason: row['reason'] as String? ?? '',
      editorId: row['editor_id'] as String?,
      editorName: row['editor_name'] as String?,
      changedFields:
          (row['changed_fields'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(),
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _addSpouse(String fromId, String toId) async {
    final Person? p = await _getPerson(fromId);
    if (p == null || p.spouseIds.contains(toId)) return;
    await _persons
        .update(<String, dynamic>{
          'spouse_ids': <String>[...p.spouseIds, toId],
        })
        .eq('id', fromId);
  }

  Future<Person?> _getPerson(String id) async {
    final Map<String, dynamic>? row = await _persons
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : _fromRow(row);
  }

  /// Creates the tree row if it doesn't exist yet (persons FK to it).
  Future<void> _ensureTree(String treeId) async {
    try {
      await _trees.upsert(
        <String, dynamic>{
          'id': treeId,
          'owner_id': _uid,
          'name': treeId == 'okonkwo' ? 'Okonkwo' : 'My Family Tree',
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _toRow(Person p) => <String, dynamic>{
    'id': p.id,
    'tree_id': p.treeId,
    'owner_id': _uid,
    'given_name': p.givenName,
    'code': p.code,
    'surname': p.surname,
    'prefix': p.prefix,
    'other_names': p.otherNames,
    'nickname': p.nickname,
    'suffix': p.suffix,
    'sex': p.sex.name,
    'birth_date': p.birthDate?.toIso8601String(),
    'death_date': p.deathDate?.toIso8601String(),
    'birth_place': p.birthPlace,
    'death_place': p.deathPlace,
    'religion': p.religion,
    'city': p.city,
    'state_province': p.stateProvince,
    'region': p.region,
    'country': p.country,
    'education': p.education,
    'language': p.language,
    'occupation': p.occupation,
    'research_notes': p.researchNotes,
    'research_questions': p.researchQuestions,
    'photo_url': p.photoUrl,
    'notes': p.notes,
    'parent_ids': p.parentIds,
    'spouse_ids': p.spouseIds,
    'events': p.events.map((e) => e.toJson()).toList(),
    'photo_gallery': p.photoGallery,
    'video_gallery': p.videoGallery,
    'voice_notes': p.voiceNotes,
  };

  Person _fromRow(Map<String, dynamic> row) {
    List<String> strList(dynamic v) =>
        (v as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList();

    return Person(
      id: row['id'] as String,
      treeId: row['tree_id'] as String,
      givenName: row['given_name'] as String? ?? '',
      code: row['code'] as String?,
      surname: row['surname'] as String? ?? '',
      prefix: row['prefix'] as String?,
      otherNames: row['other_names'] as String?,
      nickname: row['nickname'] as String?,
      suffix: row['suffix'] as String?,
      sex: Sex.values.firstWhere(
        (s) => s.name == row['sex'],
        orElse: () => Sex.unknown,
      ),
      birthDate: _parseDate(row['birth_date']),
      deathDate: _parseDate(row['death_date']),
      birthPlace: row['birth_place'] as String?,
      deathPlace: row['death_place'] as String?,
      religion: row['religion'] as String?,
      city: row['city'] as String?,
      stateProvince: row['state_province'] as String?,
      region: row['region'] as String?,
      country: row['country'] as String?,
      education: row['education'] as String?,
      language: row['language'] as String?,
      occupation: row['occupation'] as String?,
      researchNotes: row['research_notes'] as String?,
      researchQuestions: row['research_questions'] as String?,
      photoUrl: row['photo_url'] as String?,
      notes: row['notes'] as String?,
      parentIds: strList(row['parent_ids']),
      spouseIds: strList(row['spouse_ids']),
      events: ((row['events'] as List<dynamic>?) ?? const <dynamic>[])
          .map(
            (e) => TimelineEvent.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      photoGallery: strList(row['photo_gallery']),
      videoGallery: strList(row['video_gallery']),
      voiceNotes: strList(row['voice_notes']),
    );
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

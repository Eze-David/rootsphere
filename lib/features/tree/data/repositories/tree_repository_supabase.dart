import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
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
      final List<Map<String, dynamic>> rows =
          await _persons.select().eq('tree_id', treeId);
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
          await _persons.update(<String, dynamic>{
            'parent_ids': p.parentIds.where((x) => x != id).toList(),
            'spouse_ids': p.spouseIds.where((x) => x != id).toList(),
          }).eq('id', p.id);
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
    await _persons.update(<String, dynamic>{
      'parent_ids': <String>[...child.parentIds, parentId],
    }).eq('id', childId);
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _addSpouse(String fromId, String toId) async {
    final Person? p = await _getPerson(fromId);
    if (p == null || p.spouseIds.contains(toId)) return;
    await _persons.update(<String, dynamic>{
      'spouse_ids': <String>[...p.spouseIds, toId],
    }).eq('id', fromId);
  }

  Future<Person?> _getPerson(String id) async {
    final Map<String, dynamic>? row =
        await _persons.select().eq('id', id).maybeSingle();
    return row == null ? null : _fromRow(row);
  }

  /// Creates the tree row if it doesn't exist yet (persons FK to it).
  Future<void> _ensureTree(String treeId) async {
    try {
      await _trees.upsert(<String, dynamic>{
        'id': treeId,
        'owner_id': _uid,
        'name': treeId == 'okonkwo' ? 'Okonkwo' : 'My Family Tree',
      }, onConflict: 'id', ignoreDuplicates: true);
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
        'surname': p.surname,
        'other_names': p.otherNames,
        'nickname': p.nickname,
        'suffix': p.suffix,
        'sex': p.sex.name,
        'birth_date': p.birthDate?.toIso8601String(),
        'death_date': p.deathDate?.toIso8601String(),
        'birth_place': p.birthPlace,
        'death_place': p.deathPlace,
        'photo_url': p.photoUrl,
        'notes': p.notes,
        'parent_ids': p.parentIds,
        'spouse_ids': p.spouseIds,
        'events': p.events.map((e) => e.toJson()).toList(),
        'photo_gallery': p.photoGallery,
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
      surname: row['surname'] as String? ?? '',
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
      photoUrl: row['photo_url'] as String?,
      notes: row['notes'] as String?,
      parentIds: strList(row['parent_ids']),
      spouseIds: strList(row['spouse_ids']),
      events: ((row['events'] as List<dynamic>?) ?? const <dynamic>[])
          .map((e) => TimelineEvent.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
      photoGallery: strList(row['photo_gallery']),
    );
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

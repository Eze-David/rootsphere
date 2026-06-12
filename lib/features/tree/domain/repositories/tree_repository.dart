import '../entities/person.dart';

/// Persistence contract for family-tree data.
///
/// Implemented locally for Phase 2; a Supabase-backed implementation can be
/// swapped in later without touching the presentation layer.
abstract class TreeRepository {
  /// Streams all persons belonging to [treeId], emitting on every change.
  Stream<List<Person>> watchPersons(String treeId);

  /// One-shot read of all persons in [treeId].
  Future<List<Person>> getPersons(String treeId);

  /// Inserts or updates [person].
  Future<void> upsertPerson(Person person);

  /// Deletes the person with [id] and scrubs dangling references
  /// (parent / spouse links pointing at it).
  Future<void> deletePerson(String treeId, String id);

  /// Links [childId] as a child of [parentId] (adds parent to the child).
  Future<void> linkChild({
    required String treeId,
    required String parentId,
    required String childId,
  });

  /// Links two persons as spouses (symmetric).
  Future<void> linkSpouses({
    required String treeId,
    required String aId,
    required String bId,
  });
}

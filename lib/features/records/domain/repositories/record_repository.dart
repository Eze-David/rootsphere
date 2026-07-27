import '../entities/record.dart';

/// Persistence contract for source records / media (brief §Phase 3).
///
/// Implemented locally (SharedPreferences, seeded demo data) and against
/// Supabase. Searching/filtering is done in the presentation layer over the
/// streamed list, so this contract stays minimal.
abstract class RecordRepository {
  /// Streams all records in [treeId], newest first, emitting on every change.
  Stream<List<Record>> watchRecords(String treeId);

  /// Streams records across every tree the caller is allowed to see, newest
  /// first — for Supabase this is admins and approved Finders/Indexers only
  /// (enforced server-side by RLS, see
  /// 20260724000000_records_reviewer_visibility.sql); anyone else's request
  /// resolves to just their own trees' records.
  Stream<List<Record>> watchAllRecords();

  /// One-shot read of all records in [treeId].
  Future<List<Record>> getRecords(String treeId);

  /// Inserts or updates [record].
  Future<void> upsertRecord(Record record);

  /// Deletes the record with [id] from [treeId].
  Future<void> deleteRecord(String treeId, String id);
}

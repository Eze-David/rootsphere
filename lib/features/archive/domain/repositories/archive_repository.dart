import '../entities/archive_record.dart';

/// Persistence contract for the admin-only Digital Records Repository.
/// Implemented locally (SharedPreferences) and against Supabase.
/// Search/filtering happens in the presentation layer over the streamed
/// list, so this contract stays minimal — same approach as [RecordRepository].
abstract class ArchiveRepository {
  /// Streams every archive record (all statuses), newest first.
  Stream<List<ArchiveRecord>> watchAll();

  /// Inserts or updates [record] as-is (used for Save draft and edits).
  Future<void> upsertRecord(ArchiveRecord record);

  /// Moves [id] from draft to pending_review (assigns [ArchiveRecord.recordRef]
  /// server-side).
  Future<void> submitForReview(String id);

  /// Admin decision on a pending_review record: [approved] publishes it
  /// (draft → published, access becomes public), otherwise it's sent back as
  /// rejected with [note].
  Future<void> review(String id, {required bool approved, String? note});

  Future<void> deleteRecord(String id);
}

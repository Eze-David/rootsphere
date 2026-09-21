import '../entities/archive_access_request.dart';

/// Persistence contract for Permission-tier access requests. Implemented
/// locally (SharedPreferences) and against Supabase, same split as every
/// other repository in this app.
abstract class ArchiveAccessRequestRepository {
  /// The signed-in user's own requests, across every record.
  Stream<List<ArchiveAccessRequest>> watchMine();

  /// This user's request for [recordId], or null if they've never asked.
  Stream<ArchiveAccessRequest?> watchForRecord(String recordId);

  /// Creates (or re-creates, if previously rejected) a pending request.
  Future<void> request(String recordId, {String? note});

  /// All pending requests — admin review screen only (RLS blocks this from
  /// returning anything for a non-admin anyway).
  Stream<List<ArchiveAccessRequest>> watchPending();

  Future<void> review(String id, {required bool approve});
}

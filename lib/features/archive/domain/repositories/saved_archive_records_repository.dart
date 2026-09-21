/// Persistence contract for a user's bookmarked ("Save collection") archive
/// records. Implemented locally (SharedPreferences) and against Supabase.
abstract class SavedArchiveRecordsRepository {
  /// The ids of every record the signed-in user has bookmarked.
  Stream<Set<String>> watchSavedIds();

  Future<void> save(String recordId);

  Future<void> unsave(String recordId);
}

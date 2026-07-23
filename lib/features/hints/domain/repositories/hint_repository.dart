import '../entities/hint.dart';

/// Persistence contract for AI / heuristic hints (brief §Phase 4).
///
/// Implemented locally (SharedPreferences, seeded demo data) and against
/// Supabase. Ranking/filtering is done in the presentation layer over the
/// streamed list.
abstract class HintRepository {
  /// Streams all hints in [treeId], emitting on every change.
  Stream<List<Hint>> watchHints(String treeId);

  /// One-shot read of all hints in [treeId].
  Future<List<Hint>> getHints(String treeId);

  /// Inserts or updates [hint].
  Future<void> upsertHint(Hint hint);

  /// Replaces all *pending* hints in [treeId] with [hints] (used after a fresh
  /// generation pass). Accepted/dismissed hints are preserved so the user's
  /// triage decisions are not lost.
  Future<void> replacePendingHints(String treeId, List<Hint> hints);

  /// Deletes the hint with [id] from [treeId].
  Future<void> deleteHint(String treeId, String id);
}

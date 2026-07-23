import '../entities/opportunity.dart';
import '../entities/role_verification.dart';

/// Persistence contract for Finder/Indexer qualification applications. See
/// supabase/migrations/20260722020000_role_verifications.sql.
abstract class RoleVerificationRepository {
  /// The signed-in user's own applications (one per role at most).
  Stream<List<RoleVerification>> watchMine();

  /// Applies (or reapplies, e.g. after a rejection) for [role]. Always
  /// resets status to pending — the company reviews from there.
  /// [documentUrls] (certificates) and [governmentIdUrl] are already-uploaded
  /// references (see RoleVerificationStorageService).
  Future<void> apply({
    required CollaborationRole role,
    required String email,
    required String phone,
    required String governmentIdUrl,
    String? note,
    List<String> documentUrls = const <String>[],
  });

  /// Whether the signed-in user is a platform admin ("the company") —
  /// gates the review screen. Checked server-side regardless via RLS; this
  /// is only for deciding whether to show the entry point.
  Future<bool> isAdmin();

  /// All pending applications, for the admin review screen.
  Stream<List<RoleVerification>> watchPending();

  Future<void> review(String id, {required bool approve});
}

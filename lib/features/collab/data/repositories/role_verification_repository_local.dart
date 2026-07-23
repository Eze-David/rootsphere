import '../../domain/entities/opportunity.dart';
import '../../domain/entities/role_verification.dart';
import '../../domain/repositories/role_verification_repository.dart';

/// Offline/no-Supabase fallback. Qualification review is inherently a
/// multi-user, server-mediated process, so there's nothing meaningful to
/// simulate locally.
class RoleVerificationRepositoryLocal implements RoleVerificationRepository {
  @override
  Stream<List<RoleVerification>> watchMine() =>
      Stream<List<RoleVerification>>.value(const <RoleVerification>[]);

  @override
  Future<void> apply({
    required CollaborationRole role,
    required String email,
    required String phone,
    required String governmentIdUrl,
    String? note,
    List<String> documentUrls = const <String>[],
  }) async {}

  @override
  Future<bool> isAdmin() async => false;

  @override
  Stream<List<RoleVerification>> watchPending() =>
      Stream<List<RoleVerification>>.value(const <RoleVerification>[]);

  @override
  Future<void> review(String id, {required bool approve}) async {}
}

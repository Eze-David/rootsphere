import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/role_verification_repository_local.dart';
import '../../data/repositories/role_verification_repository_supabase.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/role_verification.dart';
import '../../domain/repositories/role_verification_repository.dart';

final roleVerificationRepositoryProvider = Provider<RoleVerificationRepository>(
  (ref) {
    if (SupabaseConfig.isReady) {
      return RoleVerificationRepositorySupabase(SupabaseConfig.client);
    }
    return RoleVerificationRepositoryLocal();
  },
);

/// The signed-in user's own Finder/Indexer applications. autoDispose +
/// watching authStateProvider so switching accounts re-subscribes instead
/// of showing the previous account's applications (same fix as
/// activeTreeIdProvider and friends).
final myRoleVerificationsProvider =
    StreamProvider.autoDispose<List<RoleVerification>>((ref) {
      ref.watch(authStateProvider);
      return ref.watch(roleVerificationRepositoryProvider).watchMine();
    });

/// This user's status for [role], or null if they've never applied.
final myVerificationForRoleProvider = Provider.autoDispose
    .family<RoleVerification?, CollaborationRole>((ref, role) {
      final List<RoleVerification> mine =
          ref.watch(myRoleVerificationsProvider).value ??
          const <RoleVerification>[];
      for (final v in mine) {
        if (v.role == role) return v;
      }
      return null;
    });

/// Whether the signed-in user can review applications ("the company").
final isPlatformAdminProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(roleVerificationRepositoryProvider).isAdmin();
});

/// All pending applications — admin review screen only (RLS blocks this
/// from returning anything for a non-admin anyway).
final pendingRoleVerificationsProvider =
    StreamProvider.autoDispose<List<RoleVerification>>((ref) {
      ref.watch(authStateProvider);
      return ref.watch(roleVerificationRepositoryProvider).watchPending();
    });

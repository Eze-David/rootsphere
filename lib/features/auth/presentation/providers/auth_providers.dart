import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Singleton [AuthRepository] for the app.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

/// Streams the current authenticated user (or null). Used by the router's
/// redirect guard and by screens that need the active session.
final authStateProvider = StreamProvider<AppUser?>((ref) {
  final AuthRepository repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges();
});

/// Synchronous best-effort view of whether a user is signed in.
final isSignedInProvider = Provider<bool>((ref) {
  final AsyncValue<AppUser?> state = ref.watch(authStateProvider);
  return state.maybeWhen(data: (user) => user != null, orElse: () => false);
});

/// Whether the user just landed via a password-reset email link — the
/// router forces navigation to the "set new password" screen while this is
/// true. See docs/auth-email-links.md.
final passwordRecoveryProvider = StreamProvider<bool>((ref) {
  final AuthRepository repo = ref.watch(authRepositoryProvider);
  return repo.passwordRecoveryEvents();
});

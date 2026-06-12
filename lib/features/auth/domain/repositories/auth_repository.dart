import '../entities/app_user.dart';

/// Abstract authentication contract implemented in the data layer.
///
/// Covers brief §5.1: email/password, OAuth (Google, Apple), password reset,
/// and session management.
abstract class AuthRepository {
  /// Emits the current [AppUser] whenever the auth session changes
  /// (sign-in, sign-out, token refresh). Emits `null` when signed out.
  Stream<AppUser?> authStateChanges();

  /// The currently authenticated user, or `null` if signed out.
  AppUser? get currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  });

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Updates the current user's password.
  Future<void> updatePassword(String newPassword);

  /// Permanently deletes the current user's account.
  Future<void> deleteAccount();

  /// Resends the email-confirmation message for [email].
  Future<void> resendEmailConfirmation(String email);
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Supabase-backed [AuthRepository].
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({GoTrueClient? auth})
    : _auth =
          auth ?? (SupabaseConfig.isReady ? SupabaseConfig.client.auth : null);

  final GoTrueClient? _auth;

  GoTrueClient get _client {
    final GoTrueClient? auth = _auth;
    if (auth == null) {
      throw const AuthFailure(
        'Supabase is not configured. Add credentials to your .env file.',
      );
    }
    return auth;
  }

  AppUser? _mapUser(User? user) {
    if (user == null) return null;
    final Map<String, dynamic> meta = user.userMetadata ?? <String, dynamic>{};
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      displayName: meta['display_name'] as String? ?? meta['name'] as String?,
      avatarUrl: meta['avatar_url'] as String?,
    );
  }

  @override
  Stream<AppUser?> authStateChanges() {
    if (_auth == null) return Stream<AppUser?>.value(null);
    return _client.onAuthStateChange.map(
      (AuthState state) => _mapUser(state.session?.user),
    );
  }

  @override
  AppUser? get currentUser =>
      _auth == null ? null : _mapUser(_auth.currentUser);

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _guard(
      () => _client.signInWithPassword(email: email, password: password),
    );
  }

  @override
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _guard(() => _client.signUp(email: email, password: password));
  }

  @override
  Future<void> signInWithGoogle() {
    return _guard(() => _client.signInWithOAuth(OAuthProvider.google));
  }

  @override
  Future<void> signInWithApple() {
    return _guard(() => _client.signInWithOAuth(OAuthProvider.apple));
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _guard(() => _client.resetPasswordForEmail(email));
  }

  @override
  Future<void> signOut() => _guard(() => _client.signOut());

  @override
  Future<void> updatePassword(String newPassword) {
    return _guard(() => _client.updateUser(
          UserAttributes(password: newPassword),
        ));
  }

  @override
  Future<void> deleteAccount() {
    // Client-side user deletion requires a backend RPC (e.g. `delete_user()`)
    // because Supabase does not expose admin APIs to anon keys.
    return _guard(() => SupabaseConfig.client.rpc('delete_user'));
  }

  @override
  Future<void> resendEmailConfirmation(String email) {
    return _guard(
      () => _client.resend(
        type: OtpType.signup,
        email: email,
      ),
    );
  }

  /// Wraps Supabase calls, converting low-level errors into [Failure]s.
  Future<void> _guard(Future<Object?> Function() action) async {
    try {
      await action();
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const ServerFailure();
    }
  }
}

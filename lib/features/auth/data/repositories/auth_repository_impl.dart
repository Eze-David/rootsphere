import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Supabase-backed [AuthRepository].
///
/// Google/Apple sign-in prefer each platform's native SDK (best practice for
/// production: no in-app WebView, Face ID/One Tap where available, and — for
/// Apple on iOS — what Apple's App Store review actually expects). Where the
/// native SDK isn't applicable (web always; Apple on Android, which has no
/// OS-level Apple ID), it falls back to Supabase's browser-redirect OAuth
/// flow, which still works fine there. See docs/google-apple-sign-in.md for
/// the credentials this depends on.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({GoTrueClient? auth})
    : _auth =
          auth ?? (SupabaseConfig.isReady ? SupabaseConfig.client.auth : null);

  final GoTrueClient? _auth;

  /// `google_sign_in` only accepts a nonce at [GoogleSignIn.initialize] time
  /// (see main.dart), not per sign-in attempt — unlike Apple below, so this
  /// is generated once per app process and reused for every Google sign-in
  /// during this session, rather than fresh per attempt.
  static final String _googleRawNonce = _generateNonce();

  /// Google's native SDK SHA-256-hashes whatever nonce it's given before
  /// embedding it in the ID token (same as Apple) — this is what
  /// [GoogleSignIn.initialize] gets in main.dart. Supabase, meanwhile, wants
  /// the un-hashed [_googleRawNonce] so it can hash it itself and compare.
  static String get googleInitNonce => _sha256OfString(_googleRawNonce);

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
    // `full_name` is what sign-up and OAuth providers populate; `name`/
    // `display_name` are kept as fallbacks for any other source of truth.
    // Everywhere else in the app (edit history, opportunity requester/claimer
    // names) reads `full_name` first too — keep this in sync with those
    // rather than introducing a second convention.
    final String? name =
        meta['full_name'] as String? ??
        meta['name'] as String? ??
        meta['display_name'] as String?;
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      displayName: (name?.trim().isNotEmpty ?? false) ? name!.trim() : null,
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
  Stream<bool> passwordRecoveryEvents() {
    if (_auth == null) return Stream<bool>.value(false);
    return _client.onAuthStateChange.map(
      (AuthState state) => state.event == AuthChangeEvent.passwordRecovery,
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
    required String fullName,
    required String email,
    required String password,
  }) {
    return _guard(
      () => _client.signUp(
        email: email,
        password: password,
        data: <String, dynamic>{'full_name': fullName.trim()},
        // Native only — a browser can't resolve a custom scheme, and web
        // falls back to Supabase's configured Site URL instead. See
        // docs/auth-email-links.md.
        emailRedirectTo: kIsWeb ? null : 'rootsphere://confirm-email',
      ),
    );
  }

  @override
  Future<void> signInWithGoogle() {
    // GoogleSignIn.instance.initialize() (main.dart, app start-up) is what
    // native `authenticate()` below depends on; without real credentials
    // configured there's nothing to fall back to except the redirect flow.
    if (kIsWeb || !Env.isGoogleSignInConfigured) {
      // Without an explicit redirectTo, Supabase's /authorize endpoint omits
      // redirect_to entirely and the OAuth round trip can come back to
      // whatever origin got cached earlier in the flow (e.g. a dev server
      // from a previous session) instead of wherever this page is actually
      // being served from right now. The trailing slash matters: Supabase's
      // dashboard "Redirect URLs" allow-list entry is a glob pattern
      // (`https://www.rootsphere.ink/**`), which only matches a path
      // starting with `/` — a bare origin with no trailing slash doesn't
      // match, so it'd silently fall back to the Site URL instead.
      return _guard(
        () => _client.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: kIsWeb ? '${Uri.base.origin}/' : null,
        ),
      );
    }
    return _guard(() async {
      try {
        final GoogleSignInAccount account = await GoogleSignIn.instance
            .authenticate();
        final String? idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthFailure('Google did not return an ID token.');
        }
        await _client.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          nonce: _googleRawNonce,
        );
        return null;
      } on GoogleSignInException catch (e) {
        // User closing the account picker isn't a failure worth surfacing.
        if (e.code == GoogleSignInExceptionCode.canceled) return null;
        throw AuthFailure(_googleErrorMessage(e.code));
      }
    });
  }

  /// Maps Google's native error codes to copy a user can act on —
  /// [GoogleSignInException.description] is explicitly documented as
  /// developer-facing debug detail, not something to show a user.
  static String _googleErrorMessage(GoogleSignInExceptionCode code) {
    switch (code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in isn\'t set up correctly for this app yet. '
            'Please try email sign-in instead.';
      case GoogleSignInExceptionCode.uiUnavailable:
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.unknownError:
      case GoogleSignInExceptionCode.userMismatch:
      case GoogleSignInExceptionCode.canceled:
        return 'Google sign-in didn\'t go through. Please try again.';
    }
  }

  @override
  Future<void> signInWithApple() {
    // Apple's native, Face ID-backed sheet only exists on Apple platforms;
    // elsewhere (Android has no OS-level Apple ID; web) fall back to the
    // browser-redirect flow. The App Store review requirement to offer Sign
    // in with Apple natively only applies to iOS anyway.
    if (kIsWeb || !(Platform.isIOS || Platform.isMacOS)) {
      return _guard(
        () => _client.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: kIsWeb ? '${Uri.base.origin}/' : null,
        ),
      );
    }
    return _guard(() async {
      try {
        final String rawNonce = _generateNonce();
        final AuthorizationCredentialAppleID credential =
            await SignInWithApple.getAppleIDCredential(
              scopes: const <AppleIDAuthorizationScopes>[
                AppleIDAuthorizationScopes.email,
                AppleIDAuthorizationScopes.fullName,
              ],
              nonce: _sha256OfString(rawNonce),
            );
        final String? idToken = credential.identityToken;
        if (idToken == null) {
          throw const AuthFailure('Apple did not return an identity token.');
        }
        await _client.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
        // Apple only ever sends the user's name on the FIRST authorization
        // for this app — capture it into our own metadata now, or it's gone
        // for every sign-in after this one.
        final String fullName = <String?>[
          credential.givenName,
          credential.familyName,
        ].whereType<String>().join(' ').trim();
        if (fullName.isNotEmpty) {
          await _client.updateUser(
            UserAttributes(data: <String, dynamic>{'full_name': fullName}),
          );
        }
        return null;
      } on SignInWithAppleAuthorizationException catch (e) {
        if (e.code == AuthorizationErrorCode.canceled) return null;
        throw AuthFailure(_appleErrorMessage(e.code));
      }
    });
  }

  /// Maps Apple's native error codes to copy a user can act on — the SDK's
  /// own [SignInWithAppleAuthorizationException.message] is an internal
  /// OS-level string (e.g. "com.apple.AuthenticationServices...error 1000")
  /// not meant for display.
  static String _appleErrorMessage(AuthorizationErrorCode code) {
    switch (code) {
      case AuthorizationErrorCode.notInteractive:
      case AuthorizationErrorCode.notHandled:
      case AuthorizationErrorCode.unknown:
        return 'Apple sign-in isn\'t available right now — make sure '
            'you\'re signed into iCloud on this device, then try again.';
      case AuthorizationErrorCode.failed:
      case AuthorizationErrorCode.invalidResponse:
      case AuthorizationErrorCode.credentialExport:
      case AuthorizationErrorCode.credentialImport:
      case AuthorizationErrorCode.matchedExcludedCredential:
      case AuthorizationErrorCode.canceled:
        return 'Apple sign-in didn\'t go through. Please try again.';
    }
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _guard(
      () => _client.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : 'rootsphere://reset-password',
      ),
    );
  }

  @override
  Future<void> signOut() => _guard(() => _client.signOut());

  @override
  Future<void> updatePassword(String newPassword) {
    return _guard(
      () => _client.updateUser(UserAttributes(password: newPassword)),
    );
  }

  @override
  Future<void> deleteAccount() {
    // Client-side user deletion requires a backend RPC (e.g. `delete_user()`)
    // because Supabase does not expose admin APIs to anon keys.
    return _guard(() => SupabaseConfig.client.rpc('delete_user'));
  }

  @override
  Future<void> resendEmailConfirmation(String email) {
    return _guard(() => _client.resend(type: OtpType.signup, email: email));
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

  /// A cryptographically random string sent to Apple as a hash and back to
  /// Supabase in the clear, so Supabase can confirm the identity token it
  /// receives was issued for *this* sign-in attempt and not replayed.
  static String _generateNonce([int length = 32]) {
    const String charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static String _sha256OfString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}

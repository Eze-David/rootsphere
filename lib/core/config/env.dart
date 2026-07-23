import 'package:envied/envied.dart';

part 'env.g.dart';

/// Compile-time environment variables loaded from the `.env` file via `envied`.
///
/// Never commit a populated `.env`. See `.env.example` for the required keys.
/// API keys for server-side AI calls live in Supabase Edge Functions and are
/// intentionally NOT present here.
@Envied(path: '.env', obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'SUPABASE_URL', defaultValue: '')
  static final String supabaseUrl = _Env.supabaseUrl;

  @EnviedField(varName: 'SUPABASE_ANON_KEY', defaultValue: '')
  static final String supabaseAnonKey = _Env.supabaseAnonKey;

  /// The "Web application" OAuth client id from Google Cloud Console. Used as
  /// `serverClientId` on every platform so the ID token's audience matches
  /// what's configured for the Google provider in the Supabase dashboard —
  /// see docs/google-apple-sign-in.md.
  @EnviedField(varName: 'GOOGLE_WEB_CLIENT_ID', defaultValue: '')
  static final String googleWebClientId = _Env.googleWebClientId;

  /// The iOS OAuth client id from Google Cloud Console. Only required on iOS.
  @EnviedField(varName: 'GOOGLE_IOS_CLIENT_ID', defaultValue: '')
  static final String googleIosClientId = _Env.googleIosClientId;

  /// The Apple "Services ID" identifier — required for the web-based Apple
  /// sign-in flow (Android; iOS uses the native flow and doesn't need this).
  @EnviedField(varName: 'APPLE_SERVICE_ID', defaultValue: '')
  static final String appleServiceId = _Env.appleServiceId;

  /// True when both Supabase credentials have been provided.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isGoogleSignInConfigured => googleWebClientId.isNotEmpty;
}

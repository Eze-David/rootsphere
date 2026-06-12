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

  /// True when both Supabase credentials have been provided.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

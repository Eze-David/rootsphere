import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Initialises the Supabase client once at app start-up.
///
/// When credentials are absent (e.g. a fresh clone without a populated `.env`)
/// the app still boots so the UI/design system can be reviewed — network calls
/// will simply fail until real credentials are supplied.
abstract class SupabaseConfig {
  SupabaseConfig._();

  static bool _initialized = false;

  static bool get isReady => _initialized;

  static Future<void> initialize() async {
    if (!Env.isConfigured) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
    _initialized = true;
  }

  /// Convenience accessor for the configured client.
  static SupabaseClient get client => Supabase.instance.client;
}

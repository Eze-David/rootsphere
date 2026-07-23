import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/supabase_config.dart';
import 'core/storage/preferences_provider.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  // Must be initialized exactly once, before any call to
  // GoogleSignIn.instance.authenticate() (see AuthRepositoryImpl). Skipped
  // when unconfigured/on web, where sign-in falls back to the OAuth redirect
  // flow instead — see docs/google-apple-sign-in.md.
  if (!kIsWeb && Env.isGoogleSignInConfigured) {
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS ? Env.googleIosClientId : null,
      serverClientId: Env.googleWebClientId,
      nonce: AuthRepositoryImpl.googleInitNonce,
    );
  }
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const RootsphereApp(),
    ),
  );
}

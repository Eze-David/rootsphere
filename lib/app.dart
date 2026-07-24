import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/supabase_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/presentation/providers/settings_provider.dart';

/// Root application widget — wires the theme and the go_router instance.
class RootsphereApp extends ConsumerStatefulWidget {
  const RootsphereApp({super.key});

  @override
  ConsumerState<RootsphereApp> createState() => _RootsphereAppState();
}

class _RootsphereAppState extends ConsumerState<RootsphereApp>
    with WidgetsBindingObserver {
  String? _lastProcessedAuthCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_recheckAuthCodeInUrl());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recheckAuthCodeInUrl());
    }
  }

  /// `supabase_flutter` only reads the browser URL for a password-reset or
  /// confirm-email `code` once, at engine start-up. If the link opens in a
  /// tab the browser reuses (rather than a fresh page load — common when
  /// tapping an email link on Android while the app is already open), that
  /// code is never picked up and the app is silently left on whatever it was
  /// already showing. Re-checking on every resume catches that case too.
  Future<void> _recheckAuthCodeInUrl() async {
    if (!kIsWeb || !SupabaseConfig.isReady) return;
    final String? code = Uri.base.queryParameters['code'];
    if (code == null || code == _lastProcessedAuthCode) return;
    _lastProcessedAuthCode = code;
    try {
      await SupabaseConfig.client.auth.getSessionFromUrl(Uri.base);
    } catch (_) {
      // Already consumed/expired, or handled by the library's own initial
      // check — either way there's nothing actionable to do here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp.router(
      title: 'Rootsphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: router,
    );
  }
}

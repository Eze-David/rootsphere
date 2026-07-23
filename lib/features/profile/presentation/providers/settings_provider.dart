import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_provider.dart';

/// Persistent user preferences for the app.
class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.notificationsEnabled,
    required this.languageCode,
  });

  final ThemeMode themeMode;
  final bool notificationsEnabled;
  final String languageCode;

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? notificationsEnabled,
    String? languageCode,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}

class SettingsController extends Notifier<SettingsState> {
  static const String _kTheme = 'settings_theme_mode';
  static const String _kNotifications = 'settings_notifications';
  static const String _kLanguage = 'settings_language';

  dynamic get _prefs => ref.read(sharedPreferencesProvider);

  @override
  SettingsState build() {
    final prefs = _prefs;
    final String? raw = prefs.getString(_kTheme);
    final themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
    return SettingsState(
      themeMode: themeMode,
      notificationsEnabled: prefs.getBool(_kNotifications) ?? true,
      languageCode: prefs.getString(_kLanguage) ?? 'en',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_kTheme, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setNotifications(bool enabled) async {
    await _prefs.setBool(_kNotifications, enabled);
    state = state.copyWith(notificationsEnabled: enabled);
  }

  Future<void> setLanguage(String code) async {
    await _prefs.setString(_kLanguage, code);
    state = state.copyWith(languageCode: code);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

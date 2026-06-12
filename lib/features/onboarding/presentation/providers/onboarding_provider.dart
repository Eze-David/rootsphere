import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/preferences_provider.dart';

const String _kOnboardingCompleteKey = 'onboarding_complete';

/// Tracks whether the user has finished the one-time onboarding flow.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_kOnboardingCompleteKey) ?? false;
  }

  Future<void> complete() async {
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_kOnboardingCompleteKey, true);
    state = true;
  }
}

final onboardingCompleteProvider = NotifierProvider<OnboardingController, bool>(
  OnboardingController.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/preferences_provider.dart';
import 'app_routes.dart';

const String _kLastTabKey = 'last_tab_path';

/// Bottom-nav tab root paths, in the same order as the shell's branches.
const List<String> kShellTabPaths = <String>[
  AppRoutes.home,
  AppRoutes.tree,
  AppRoutes.records,
  AppRoutes.collab,
  AppRoutes.profile,
];

/// Remembers which bottom-nav tab the user was last on, so quitting and
/// reopening the app resumes there instead of always landing back on Home.
class LastTabController extends Notifier<String> {
  @override
  String build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    final String? stored = prefs.getString(_kLastTabKey);
    return kShellTabPaths.contains(stored) ? stored! : AppRoutes.home;
  }

  Future<void> setTab(String path) async {
    if (!kShellTabPaths.contains(path) || state == path) return;
    state = path;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kLastTabKey, path);
  }
}

final lastTabProvider = NotifierProvider<LastTabController, String>(
  LastTabController.new,
);

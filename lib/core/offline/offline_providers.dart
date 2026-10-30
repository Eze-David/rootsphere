import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_provider.dart';
import 'offline_cache.dart';

/// Whether the device has any network interface up (Wi-Fi, mobile data,
/// ethernet…). A `true` here doesn't guarantee the internet is reachable —
/// repositories still treat failed requests as offline (see
/// `isNetworkError`) — but a `false` is reliable, and the false → true edge
/// is what triggers re-syncing queued changes.
bool _isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

/// Online/offline changes, de-duplicated. Starts with the current state.
Stream<bool> watchOnline() async* {
  final Connectivity connectivity = Connectivity();
  bool? last;
  try {
    last = _isOnline(await connectivity.checkConnectivity());
  } catch (_) {
    last = true;
  }
  yield last;
  await for (final List<ConnectivityResult> results
      in connectivity.onConnectivityChanged) {
    final bool online = _isOnline(results);
    if (online != last) {
      last = online;
      yield online;
    }
  }
}

/// Live online/offline state for the UI (the offline banner). Assumed online
/// until the first check completes so the banner never flashes on launch.
final isOnlineProvider = StreamProvider<bool>((ref) => watchOnline());

/// Device-side copies of server data (see [OfflineCache]).
final offlineCacheProvider = Provider<OfflineCache>((ref) {
  return OfflineCache(ref.watch(sharedPreferencesProvider));
});

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../error/failure.dart';

/// Device-side copies of server data, so screens keep showing the last thing
/// they loaded when the network is gone.
///
/// Values are stored as JSON strings in [SharedPreferences] (localStorage on
/// the web) under keys starting with [prefix], which lets [clear] wipe them
/// all on sign-out without touching other preferences.
class OfflineCache {
  OfflineCache(this._prefs);

  final SharedPreferences _prefs;

  static const String prefix = 'offline_cache_';

  /// How long a request may take before it's treated as "offline" and the
  /// cached copy is used instead.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Delay before a failed live stream is re-opened (it's also re-opened as
  /// soon as connectivity returns).
  static const Duration retryDelay = Duration(seconds: 30);

  T? read<T>(String key, T Function(Object? json) decode) {
    final String? raw = _prefs.getString('$prefix$key');
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void write(String key, Object? json) {
    unawaited(_prefs.setString('$prefix$key', jsonEncode(json)));
  }

  /// Removes every cached copy (called on sign-out so the next account on
  /// this device can't see the previous one's data).
  Future<void> clear() async {
    for (final String key in _prefs.getKeys().toList()) {
      if (key.startsWith(prefix)) await _prefs.remove(key);
    }
  }

  /// One-shot read: the live result when reachable (refreshing the cached
  /// copy), otherwise the cached copy. Server errors are rethrown as-is.
  Future<T> future<T>({
    required String key,
    required Future<T> Function() remote,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
  }) async {
    try {
      final T value = await remote().timeout(requestTimeout);
      write(key, encode(value));
      return value;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final T? cached = read(key, decode);
      if (cached != null) return cached;
      throw const NetworkFailure();
    }
  }

  /// A live stream that starts with the cached copy (if any), then follows
  /// [remote]. When [remote] fails it is re-opened after [retryDelay] or as
  /// soon as [onlineChanges] reports the network is back; while a cached copy
  /// exists the failure is hidden, so screens keep their data offline.
  Stream<T> stream<T>({
    required String key,
    required Stream<T> Function() remote,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
    required Stream<bool> onlineChanges,
  }) {
    StreamSubscription<T>? sub;
    StreamSubscription<bool>? onlineSub;
    Timer? retry;
    bool hasValue = false;
    late final StreamController<T> controller;

    void subscribe() {
      retry?.cancel();
      unawaited(sub?.cancel());
      sub = remote().listen(
        (T value) {
          hasValue = true;
          controller.add(value);
          write(key, encode(value));
        },
        onError: (Object e, StackTrace st) {
          unawaited(sub?.cancel());
          sub = null;
          if (!hasValue) {
            controller.addError(
              isNetworkError(e) ? const NetworkFailure() : e,
              st,
            );
          }
          retry = Timer(retryDelay, subscribe);
        },
      );
    }

    controller = StreamController<T>(
      onListen: () {
        final T? cached = read(key, decode);
        if (cached != null) {
          hasValue = true;
          controller.add(cached);
        }
        subscribe();
        // Re-open on reconnect even if the stream looks healthy — a realtime
        // channel can silently miss changes made while the device was away.
        onlineSub = onlineChanges
            .skip(1)
            .where((o) => o)
            .listen((_) => subscribe());
      },
      onCancel: () async {
        retry?.cancel();
        await onlineSub?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }
}

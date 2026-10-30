import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../error/failure.dart';
import 'offline_cache.dart';

/// How many changes are waiting to reach the server, and why the last one
/// was turned down (if it was).
class SyncStatus {
  const SyncStatus({this.pending = 0, this.error});

  final int pending;

  /// Set when the server rejected a change made offline (e.g. the user lost
  /// edit rights in the meantime); that change is dropped.
  final String? error;
}

/// One queued change. [type] and [data] are defined by the repository that
/// owns the [Outbox]; [data] must be JSON-encodable.
class OutboxOp {
  OutboxOp({required this.type, required this.data, String? id, this.uid = ''})
    : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  static int _seq = 0;

  final String id;
  final String type;
  Map<String, dynamic> data;

  /// The account that made the change.
  String uid;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'uid': uid,
    'data': data,
  };

  factory OutboxOp.fromJson(Map<String, dynamic> json) => OutboxOp(
    id: json['id'] as String,
    type: json['type'] as String,
    uid: json['uid'] as String? ?? '',
    data: Map<String, dynamic>.from(json['data'] as Map),
  );
}

/// A persistent, ordered queue of changes to replay against the server.
///
/// Repositories [add] a change (after applying it to their device copy) and
/// then [sendNow]: online, that waits for the server like a normal call and
/// rethrows its errors; offline it returns at once and the change is sent
/// when the network comes back ([flush] runs on reconnect, on a timer after
/// a failure, and whenever the owning account signs in). Changes are tagged
/// with the account that made them and only ever sent under that account.
class Outbox {
  Outbox({
    required SharedPreferences prefs,
    required String storageKey,
    required String Function() currentUid,
    required Future<void> Function(OutboxOp op) send,
    required void Function(OutboxOp op, {required bool synced}) onDone,
    required Stream<bool> onlineChanges,
    void Function()? onReconnect,
  }) : _prefs = prefs,
       _storageKey = storageKey,
       _currentUid = currentUid,
       _send = send,
       _onDone = onDone,
       _onReconnect = onReconnect {
    _ops = _load();
    _onlineSub = onlineChanges.listen(_onOnlineChanged);
  }

  final SharedPreferences _prefs;
  final String _storageKey;
  final String Function() _currentUid;
  final Future<void> Function(OutboxOp op) _send;
  final void Function(OutboxOp op, {required bool synced}) _onDone;
  final void Function()? _onReconnect;

  late final List<OutboxOp> _ops;
  late final StreamSubscription<bool> _onlineSub;
  bool _online = true;

  final StreamController<SyncStatus> _status =
      StreamController<SyncStatus>.broadcast();
  String? _lastError;

  Future<void>? _flushing;
  bool _stalled = false;
  Timer? _retry;

  /// Ops a caller is awaiting, and the server error for any that were rejected.
  final Set<String> _awaited = <String>{};
  final Map<String, Object> _rejected = <String, Object>{};

  static const Duration _awaitLimit = Duration(seconds: 8);

  /// Queued changes belonging to the signed-in account, oldest first.
  /// Changes made by another account on this device wait until that account
  /// signs back in.
  List<OutboxOp> get mine {
    final String uid = _currentUid();
    if (uid.isEmpty) return <OutboxOp>[];
    return _ops.where((op) => op.uid == uid).toList();
  }

  SyncStatus get status => SyncStatus(pending: mine.length, error: _lastError);

  Stream<SyncStatus> watchStatus() async* {
    yield status;
    yield* _status.stream;
  }

  void clearError() {
    _lastError = null;
    _notify();
  }

  /// Queues [op] for the signed-in account.
  void add(OutboxOp op) {
    op.uid = _currentUid();
    _ops.add(op);
    _save();
    _notify();
  }

  /// Persists a change to a queued op's [OutboxOp.data] (e.g. an attachment
  /// that has now been uploaded), so a retry doesn't redo that work.
  void update(OutboxOp op) {
    if (_ops.contains(op)) _save();
  }

  /// Tries to send [op] (and anything queued before it) now. Returns once it
  /// has synced, or straight away (after a short wait at most) if the device
  /// is offline. Throws if the server rejected it.
  Future<void> sendNow(OutboxOp op) async {
    if (!_online) return;
    _awaited.add(op.id);
    try {
      await flush().timeout(_awaitLimit);
      // A flush already in progress may have finished its loop just before
      // this op was added.
      if (_ops.contains(op) && !_stalled) {
        await flush().timeout(_awaitLimit);
      }
    } on TimeoutException {
      // Slow network: leave it syncing in the background.
    } finally {
      _awaited.remove(op.id);
    }
    final Object? error = _rejected.remove(op.id);
    if (error != null) throw error;
  }

  /// Sends queued changes to the server, oldest first. Safe to call any time;
  /// concurrent calls share one run.
  Future<void> flush() =>
      _flushing ??= _runFlush().whenComplete(() => _flushing = null);

  Future<void> _runFlush() async {
    _stalled = false;
    while (true) {
      final List<OutboxOp> queue = mine;
      if (queue.isEmpty) break;
      final OutboxOp op = queue.first;
      bool rejected = false;
      try {
        await _send(op);
      } catch (e) {
        if (_isRetryable(e)) {
          _stalled = true;
          _scheduleRetry();
          break;
        }
        rejected = true;
        _lastError = friendlyErrorMessage(e);
        if (_awaited.contains(op.id)) _rejected[op.id] = e;
      }
      _ops.remove(op);
      _save();
      _onDone(op, synced: !rejected);
      _notify();
    }
  }

  /// Network trouble, or an access token that expired while offline and
  /// hasn't been refreshed yet — keep the change and try again later rather
  /// than dropping it.
  static bool _isRetryable(Object e) {
    if (isNetworkError(e)) return true;
    final String raw = e.toString().toLowerCase();
    return raw.contains('jwt') ||
        raw.contains('pgrst301') ||
        raw.contains('pgrst303');
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(OfflineCache.retryDelay, () => unawaited(flush()));
  }

  void _onOnlineChanged(bool online) {
    _online = online;
    if (!online) return;
    unawaited(flush());
    _onReconnect?.call();
  }

  void _notify() {
    if (!_status.isClosed) _status.add(status);
  }

  List<OutboxOp> _load() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null) return <OutboxOp>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => OutboxOp.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <OutboxOp>[];
    }
  }

  void _save() {
    unawaited(
      _prefs.setString(
        _storageKey,
        jsonEncode(_ops.map((op) => op.toJson()).toList()),
      ),
    );
  }

  void dispose() {
    _retry?.cancel();
    unawaited(_onlineSub.cancel());
    unawaited(_status.close());
  }
}

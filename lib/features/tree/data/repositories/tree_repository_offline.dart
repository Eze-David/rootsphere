import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/offline/offline_cache.dart';
import '../../../../core/offline/outbox.dart';
import '../../domain/entities/edit_history_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/repositories/tree_repository.dart';

/// Offline-first [TreeRepository] in front of the Supabase one.
///
/// * Reads come from a device copy of each tree (the last server snapshot),
///   kept fresh from the live stream whenever the network is up.
/// * Writes are applied to the device copy straight away and queued in an
///   [Outbox], which replays them against [_remote] in order. While online
///   this happens immediately and server errors are thrown back to the caller
///   as before; offline the call succeeds and the change syncs on reconnect.
/// * What's shown is always "server snapshot + queued changes", so a live
///   update arriving mid-sync never makes a pending edit flicker away.
///
/// Conflicts are last-write-wins per person: a queued edit replaces that
/// person's row when it syncs.
class TreeRepositoryOffline implements TreeRepository {
  TreeRepositoryOffline({
    required TreeRepository remote,
    required SharedPreferences prefs,
    required OfflineCache cache,
    required String Function() currentUid,
    required Stream<bool> onlineChanges,
  }) : _remote = remote,
       _cache = cache {
    _outbox = Outbox(
      prefs: prefs,
      storageKey: 'offline_outbox_tree',
      currentUid: currentUid,
      send: (op) => _send(op).timeout(OfflineCache.requestTimeout),
      onDone: _onSynced,
      onlineChanges: onlineChanges,
      // A realtime channel can silently miss changes made while the device
      // was away, so re-open every live tree stream on reconnect.
      onReconnect: () => _channels.keys.toList().forEach(_subscribe),
    );
  }

  final TreeRepository _remote;
  final OfflineCache _cache;
  late final Outbox _outbox;

  final Map<String, _TreeChannel> _channels = <String, _TreeChannel>{};

  // ── Sync status ─────────────────────────────────────────────────────────

  SyncStatus get status => _outbox.status;

  Stream<SyncStatus> watchStatus() => _outbox.watchStatus();

  void clearError() => _outbox.clearError();

  /// Sends queued changes now (see [Outbox.flush]).
  Future<void> flush() => _outbox.flush();

  void dispose() {
    _outbox.dispose();
    for (final _TreeChannel ch in _channels.values) {
      ch.stop();
    }
  }

  // ── Reads ────────────────────────────────────────────────────────────────

  @override
  Stream<List<Person>> watchPersons(String treeId) {
    late final StreamController<List<Person>> controller;
    controller = StreamController<List<Person>>(
      onListen: () {
        final _TreeChannel ch = _channels.putIfAbsent(treeId, _TreeChannel.new);
        ch.sinks.add(controller);
        final List<Person>? local = _localView(treeId);
        if (local != null) controller.add(local);
        if (ch.remoteSub == null) _subscribe(treeId);
      },
      onCancel: () {
        final _TreeChannel? ch = _channels[treeId];
        if (ch == null) return;
        ch.sinks.remove(controller);
        if (ch.sinks.isEmpty) {
          ch.stop();
          _channels.remove(treeId);
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Person>> getPersons(String treeId) async {
    try {
      final List<Person> persons = await _remote
          .getPersons(treeId)
          .timeout(OfflineCache.requestTimeout);
      _writeSnapshot(treeId, persons);
      return _apply(persons, _pendingFor(treeId));
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final List<Person>? local = _localView(treeId);
      if (local != null) return local;
      throw const NetworkFailure();
    }
  }

  @override
  Future<List<EditHistoryEntry>> getEditHistory(String personId) async {
    final List<EditHistoryEntry> server = await _historyOrCached(
      'person_edits_$personId',
      () => _remote.getEditHistory(personId),
    );
    final List<EditHistoryEntry> pending = <EditHistoryEntry>[
      for (final OutboxOp op in _outbox.mine)
        if (op.entry?.personId == personId) op.entry!,
    ];
    return _mergeHistory(pending, server);
  }

  @override
  Future<List<EditHistoryEntry>> getRecentEditHistory(
    String treeId, {
    int limit = 20,
  }) async {
    final List<EditHistoryEntry> server = await _historyOrCached(
      'recent_edits_$treeId',
      () => _remote.getRecentEditHistory(treeId, limit: limit),
    );
    final List<EditHistoryEntry> pending = <EditHistoryEntry>[
      for (final OutboxOp op in _pendingFor(treeId))
        if (op.entry != null) op.entry!,
    ];
    return _mergeHistory(pending, server).take(limit).toList();
  }

  Future<List<EditHistoryEntry>> _historyOrCached(
    String key,
    Future<List<EditHistoryEntry>> Function() remote,
  ) async {
    try {
      return await _cache.future<List<EditHistoryEntry>>(
        key: key,
        remote: remote,
        encode: (list) => list.map((e) => e.toJson()).toList(),
        decode: (json) => (json! as List<dynamic>)
            .map((e) => EditHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on NetworkFailure {
      // Never loaded online — history is secondary, so show it empty rather
      // than an error.
      return <EditHistoryEntry>[];
    }
  }

  /// Pending (newest first) on top of the server list, without duplicates.
  List<EditHistoryEntry> _mergeHistory(
    List<EditHistoryEntry> pending,
    List<EditHistoryEntry> server,
  ) {
    final Set<String> seen = <String>{};
    return <EditHistoryEntry>[
      ...pending.reversed,
      ...server,
    ].where((e) => seen.add(e.id)).toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  @override
  Future<void> upsertPerson(Person person) => _enqueue(
    _upsert,
    <String, dynamic>{'treeId': person.treeId, 'person': person.toJson()},
  );

  @override
  Future<void> deletePerson(String treeId, String id) =>
      _enqueue(_delete, <String, dynamic>{'treeId': treeId, 'a': id});

  @override
  Future<void> linkChild({
    required String treeId,
    required String parentId,
    required String childId,
  }) => _enqueue(_linkChild, <String, dynamic>{
    'treeId': treeId,
    'a': parentId,
    'b': childId,
  });

  @override
  Future<void> linkSpouses({
    required String treeId,
    required String aId,
    required String bId,
  }) => _enqueue(_linkSpouses, <String, dynamic>{
    'treeId': treeId,
    'a': aId,
    'b': bId,
  });

  @override
  Future<void> addEditHistory(EditHistoryEntry entry) => _enqueue(
    _history,
    <String, dynamic>{'treeId': entry.treeId, 'entry': entry.toJson()},
  );

  // Op types. `a`/`b` carry ids: the deleted person; parent and child for
  // linkChild; the two spouses for linkSpouses.
  static const String _upsert = 'upsert';
  static const String _delete = 'delete';
  static const String _linkChild = 'linkChild';
  static const String _linkSpouses = 'linkSpouses';
  static const String _history = 'history';

  Future<void> _enqueue(String type, Map<String, dynamic> data) async {
    final OutboxOp op = OutboxOp(type: type, data: data);
    _outbox.add(op);
    _emit(op.treeId);
    await _outbox.sendNow(op);
  }

  Future<void> _send(OutboxOp op) {
    switch (op.type) {
      case _upsert:
        return _remote.upsertPerson(op.person!);
      case _delete:
        return _remote.deletePerson(op.treeId, op.a!);
      case _linkChild:
        return _remote.linkChild(
          treeId: op.treeId,
          parentId: op.a!,
          childId: op.b!,
        );
      case _linkSpouses:
        return _remote.linkSpouses(treeId: op.treeId, aId: op.a!, bId: op.b!);
      case _history:
        return _remote.addEditHistory(op.entry!);
    }
    return Future<void>.value();
  }

  /// Folds a synced op into the cached server snapshot, so the view doesn't
  /// briefly revert before the live stream catches up. A rejected op just
  /// disappears from the view.
  void _onSynced(OutboxOp op, {required bool synced}) {
    if (synced) {
      final EditHistoryEntry? entry = op.entry;
      if (entry != null) {
        for (final String key in <String>[
          'person_edits_${entry.personId}',
          'recent_edits_${entry.treeId}',
        ]) {
          final List<dynamic>? list = _cache.read(
            key,
            (j) => j as List<dynamic>,
          );
          if (list != null) {
            _cache.write(key, <dynamic>[entry.toJson(), ...list]);
          }
        }
      } else {
        final List<Person>? snapshot = _readSnapshot(op.treeId);
        if (snapshot != null) {
          _writeSnapshot(op.treeId, _apply(snapshot, <OutboxOp>[op]));
        }
      }
    }
    _emit(op.treeId);
  }

  // ── Live stream per tree ─────────────────────────────────────────────────

  void _subscribe(String treeId) {
    final _TreeChannel? ch = _channels[treeId];
    if (ch == null) return;
    ch.stop();
    ch.remoteSub = _remote
        .watchPersons(treeId)
        .listen(
          (List<Person> persons) {
            _writeSnapshot(treeId, persons);
            _emit(treeId);
          },
          onError: (Object e, StackTrace st) {
            unawaited(ch.remoteSub?.cancel());
            ch.remoteSub = null;
            if (_localView(treeId) == null) {
              final Object error = isNetworkError(e)
                  ? const NetworkFailure()
                  : e;
              for (final sink in ch.sinks) {
                sink.addError(error, st);
              }
            }
            ch.retry = Timer(OfflineCache.retryDelay, () => _subscribe(treeId));
          },
        );
  }

  void _emit(String treeId) {
    final _TreeChannel? ch = _channels[treeId];
    if (ch == null) return;
    final List<Person> view = _localView(treeId) ?? <Person>[];
    for (final sink in ch.sinks) {
      sink.add(view);
    }
  }

  // ── Local state ──────────────────────────────────────────────────────────

  /// Server snapshot + this user's queued changes, or null if this tree has
  /// never been loaded on this device.
  List<Person>? _localView(String treeId) {
    final List<Person>? snapshot = _readSnapshot(treeId);
    final List<OutboxOp> pending = _pendingFor(treeId);
    if (snapshot == null && pending.isEmpty) return null;
    return _apply(snapshot ?? <Person>[], pending);
  }

  List<OutboxOp> _pendingFor(String treeId) =>
      _outbox.mine.where((op) => op.treeId == treeId).toList();

  String _snapshotKey(String treeId) => 'tree_persons_$treeId';

  List<Person>? _readSnapshot(String treeId) => _cache.read(
    _snapshotKey(treeId),
    (json) => (json! as List<dynamic>)
        .map((e) => Person.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  void _writeSnapshot(String treeId, List<Person> persons) => _cache.write(
    _snapshotKey(treeId),
    persons.map((p) => p.toJson()).toList(),
  );

  /// Applies [ops] to [base] the same way the server would — mirrors
  /// [TreeRepositorySupabase]'s mutation semantics.
  static List<Person> _apply(List<Person> base, Iterable<OutboxOp> ops) {
    final List<Person> persons = List<Person>.of(base);
    int indexOf(String id) => persons.indexWhere((p) => p.id == id);

    for (final OutboxOp op in ops) {
      switch (op.type) {
        case _upsert:
          final Person person = op.person!;
          final int i = indexOf(person.id);
          if (i >= 0) {
            persons[i] = person;
          } else {
            persons.add(person);
          }
        case _delete:
          final String id = op.a!;
          persons.removeWhere((p) => p.id == id);
          for (int i = 0; i < persons.length; i++) {
            final Person p = persons[i];
            if (p.parentIds.contains(id) || p.spouseIds.contains(id)) {
              persons[i] = p.copyWith(
                parentIds: p.parentIds.where((x) => x != id).toList(),
                spouseIds: p.spouseIds.where((x) => x != id).toList(),
              );
            }
          }
        case _linkChild:
          final int i = indexOf(op.b!);
          if (i >= 0 && !persons[i].parentIds.contains(op.a)) {
            persons[i] = persons[i].copyWith(
              parentIds: <String>[...persons[i].parentIds, op.a!],
            );
          }
        case _linkSpouses:
          for (final (String from, String to) in <(String, String)>[
            (op.a!, op.b!),
            (op.b!, op.a!),
          ]) {
            final int i = indexOf(from);
            if (i >= 0 && !persons[i].spouseIds.contains(to)) {
              persons[i] = persons[i].copyWith(
                spouseIds: <String>[...persons[i].spouseIds, to],
              );
            }
          }
      }
    }
    return persons;
  }
}

/// Typed access to a tree op's [OutboxOp.data].
extension on OutboxOp {
  String get treeId => data['treeId'] as String;
  String? get a => data['a'] as String?;
  String? get b => data['b'] as String?;
  Person? get person => data['person'] == null
      ? null
      : Person.fromJson(Map<String, dynamic>.from(data['person'] as Map));
  EditHistoryEntry? get entry => data['entry'] == null
      ? null
      : EditHistoryEntry.fromJson(
          Map<String, dynamic>.from(data['entry'] as Map),
        );
}

class _TreeChannel {
  final Set<StreamController<List<Person>>> sinks =
      <StreamController<List<Person>>>{};
  StreamSubscription<List<Person>>? remoteSub;
  Timer? retry;

  void stop() {
    retry?.cancel();
    retry = null;
    unawaited(remoteSub?.cancel());
    remoteSub = null;
  }
}

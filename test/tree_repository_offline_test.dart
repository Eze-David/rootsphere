import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rootsphere/core/error/failure.dart';
import 'package:rootsphere/core/offline/offline_cache.dart';
import 'package:rootsphere/features/tree/data/repositories/tree_repository_offline.dart';
import 'package:rootsphere/features/tree/domain/entities/edit_history_entry.dart';
import 'package:rootsphere/features/tree/domain/entities/person.dart';
import 'package:rootsphere/features/tree/domain/repositories/tree_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for Supabase that can be switched "offline".
class FakeRemote implements TreeRepository {
  final Map<String, Person> rows = <String, Person>{};
  final List<EditHistoryEntry> edits = <EditHistoryEntry>[];
  final StreamController<List<Person>> live =
      StreamController<List<Person>>.broadcast();
  bool offline = false;
  Object? rejectWith;
  final List<String> calls = <String>[];

  void _check() {
    if (offline) throw const SocketException('Network is unreachable');
    if (rejectWith != null) throw rejectWith!;
  }

  void _push() => live.add(rows.values.toList());

  @override
  Stream<List<Person>> watchPersons(String treeId) {
    if (offline) {
      return Stream<List<Person>>.error(
        const SocketException('Failed host lookup'),
      );
    }
    scheduleMicrotask(_push);
    return live.stream;
  }

  @override
  Future<List<Person>> getPersons(String treeId) async {
    _check();
    return rows.values.toList();
  }

  @override
  Future<void> upsertPerson(Person person) async {
    _check();
    calls.add('upsert ${person.id}');
    rows[person.id] = person;
    _push();
  }

  @override
  Future<void> deletePerson(String treeId, String id) async {
    _check();
    calls.add('delete $id');
    rows.remove(id);
    _push();
  }

  @override
  Future<void> linkChild({
    required String treeId,
    required String parentId,
    required String childId,
  }) async {
    _check();
    calls.add('linkChild $parentId>$childId');
    final Person c = rows[childId]!;
    rows[childId] = c.copyWith(parentIds: <String>[...c.parentIds, parentId]);
    _push();
  }

  @override
  Future<void> linkSpouses({
    required String treeId,
    required String aId,
    required String bId,
  }) async {
    _check();
    calls.add('linkSpouses $aId+$bId');
  }

  @override
  Future<void> addEditHistory(EditHistoryEntry entry) async {
    _check();
    edits.insert(0, entry);
  }

  @override
  Future<List<EditHistoryEntry>> getEditHistory(String personId) async {
    _check();
    return edits.where((e) => e.personId == personId).toList();
  }

  @override
  Future<List<EditHistoryEntry>> getRecentEditHistory(
    String treeId, {
    int limit = 20,
  }) async {
    _check();
    return edits.take(limit).toList();
  }
}

Person person(String id, {List<String> parents = const <String>[]}) => Person(
  id: id,
  treeId: 't1',
  givenName: id,
  surname: 'X',
  parentIds: parents,
);

void main() {
  late FakeRemote remote;
  late SharedPreferences prefs;
  late StreamController<bool> online;
  late String uid;

  TreeRepositoryOffline build() => TreeRepositoryOffline(
    remote: remote,
    prefs: prefs,
    cache: OfflineCache(prefs),
    currentUid: () => uid,
    onlineChanges: online.stream,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    remote = FakeRemote();
    online = StreamController<bool>.broadcast();
    uid = 'u1';
  });

  test('online writes go straight to the server', () async {
    final repo = build();
    await repo.upsertPerson(person('a'));
    expect(remote.rows.keys, <String>['a']);
    expect(repo.status.pending, 0);
    repo.dispose();
  });

  test('server rejections are thrown back to the caller and dropped', () async {
    final repo = build();
    remote.rejectWith = const ServerFailure('permission denied');
    await expectLater(
      repo.upsertPerson(person('a')),
      throwsA(isA<ServerFailure>()),
    );
    expect(repo.status.pending, 0);
    expect(await prefs.getString('offline_outbox_tree'), '[]');
    repo.dispose();
  });

  test(
    'offline edits show immediately and sync in order on reconnect',
    () async {
      remote.rows['a'] = person('a');
      final repo = build();
      // Load the tree once while online so there's a device copy.
      expect((await repo.getPersons('t1')).map((p) => p.id), <String>['a']);

      remote.offline = true;
      online.add(false);
      await Future<void>.delayed(Duration.zero);

      await repo.upsertPerson(person('b'));
      await repo.linkChild(treeId: 't1', parentId: 'a', childId: 'b');
      expect(repo.status.pending, 2);
      expect(remote.calls, isEmpty);

      final List<Person> view = await repo.getPersons('t1');
      expect(view.map((p) => p.id), <String>['a', 'b']);
      expect(view.firstWhere((p) => p.id == 'b').parentIds, <String>['a']);

      remote.offline = false;
      online.add(true);
      await repo.flush();
      expect(remote.calls, <String>['upsert b', 'linkChild a>b']);
      expect(remote.rows['b']!.parentIds, <String>['a']);
      expect(repo.status.pending, 0);
      repo.dispose();
    },
  );

  test('the queue survives an app restart', () async {
    final first = build();
    remote.offline = true;
    online.add(false);
    await Future<void>.delayed(Duration.zero);
    await first.upsertPerson(person('a'));
    first.dispose();

    remote.offline = false;
    final second = build();
    expect(second.status.pending, 1);
    await second.flush();
    expect(remote.rows.keys, <String>['a']);
    second.dispose();
  });

  test("another account's queued changes wait for that account", () async {
    final repo = build();
    online.add(false);
    await Future<void>.delayed(Duration.zero);
    await repo.upsertPerson(person('a'));

    uid = 'u2';
    expect(repo.status.pending, 0);
    await repo.flush();
    expect(remote.calls, isEmpty);

    uid = 'u1';
    await repo.flush();
    expect(remote.calls, <String>['upsert a']);
    repo.dispose();
  });

  test(
    'watchPersons serves the device copy when the live stream fails',
    () async {
      remote.rows['a'] = person('a');
      final repo = build();
      await repo.getPersons('t1');

      remote.offline = true;
      final List<Person> first = await repo.watchPersons('t1').first;
      expect(first.map((p) => p.id), <String>['a']);
      repo.dispose();
    },
  );

  test('watchPersons errors when offline with nothing cached', () async {
    remote.offline = true;
    final repo = build();
    await expectLater(
      repo.watchPersons('t1').first,
      throwsA(isA<NetworkFailure>()),
    );
    repo.dispose();
  });

  test('offline edit history is merged ahead of the server list', () async {
    final repo = build();
    remote.offline = true;
    online.add(false);
    await Future<void>.delayed(Duration.zero);
    final entry = EditHistoryEntry(
      id: 'e1',
      treeId: 't1',
      personId: 'a',
      reason: 'fixed name',
      changedFields: const <String>['givenName'],
      createdAt: DateTime(2026),
    );
    await repo.addEditHistory(entry);
    expect((await repo.getEditHistory('a')).map((e) => e.id), <String>['e1']);
    repo.dispose();
  });
}

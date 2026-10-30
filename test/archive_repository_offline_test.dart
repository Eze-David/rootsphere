import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rootsphere/core/error/failure.dart';
import 'package:rootsphere/core/offline/offline_cache.dart';
import 'package:rootsphere/features/archive/data/repositories/archive_repository_offline.dart';
import 'package:rootsphere/features/archive/data/services/archive_storage_service.dart';
import 'package:rootsphere/features/archive/domain/entities/archive_record.dart';
import 'package:rootsphere/features/archive/domain/repositories/archive_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for Supabase that can be switched "offline".
class FakeArchive implements ArchiveRepository {
  final Map<String, ArchiveRecord> rows = <String, ArchiveRecord>{};
  final StreamController<List<ArchiveRecord>> live =
      StreamController<List<ArchiveRecord>>.broadcast();
  bool offline = false;
  final List<String> calls = <String>[];

  void _check() {
    if (offline) throw const SocketException('Network is unreachable');
  }

  void _push() => live.add(rows.values.toList());

  @override
  Stream<List<ArchiveRecord>> watchAll() {
    if (offline) {
      return Stream<List<ArchiveRecord>>.error(
        const SocketException('Failed host lookup'),
      );
    }
    scheduleMicrotask(_push);
    return live.stream;
  }

  @override
  Future<void> upsertRecord(ArchiveRecord record) async {
    _check();
    calls.add('upsert ${record.id} ${record.files.map((f) => f.url)}');
    rows[record.id] = record;
    _push();
  }

  @override
  Future<void> submitForReview(String id) async {
    _check();
    calls.add('submit $id');
    rows[id] = rows[id]!.copyWith(
      reviewStatus: ArchiveReviewStatus.pendingReview,
    );
    _push();
  }

  @override
  Future<void> review(String id, {required bool approved, String? note}) async {
    _check();
    calls.add('review $id $approved');
  }

  @override
  Future<void> deleteRecord(String id) async {
    _check();
    calls.add('delete $id');
    rows.remove(id);
    _push();
  }
}

/// Treats `local/…` references as files kept for upload.
class FakeStorage extends ArchiveStorageService {
  bool offline = false;
  final List<String> uploaded = <String>[];

  @override
  bool isAwaitingUpload(String reference) => reference.startsWith('local/');

  @override
  Future<StoredArchiveFile> uploadOrKeepForLater({
    required String recordId,
    required String fileName,
    required Uint8List bytes,
  }) async => offline
      ? StoredArchiveFile(
          url: 'local/$fileName',
          fileName: fileName,
          awaitingUpload: true,
        )
      : StoredArchiveFile(url: 'https://cdn/$fileName', fileName: fileName);

  @override
  Future<String> uploadKeptFile({
    required String recordId,
    required String fileName,
    required String path,
  }) async {
    if (offline) throw const NetworkFailure();
    uploaded.add(path);
    return 'https://cdn/$fileName';
  }
}

void main() {
  late FakeArchive remote;
  late FakeStorage storage;
  late SharedPreferences prefs;
  late StreamController<bool> online;

  ArchiveRepositoryOffline build() => ArchiveRepositoryOffline(
    remote: remote,
    storage: storage,
    prefs: prefs,
    cache: OfflineCache(prefs),
    currentUid: () => 'admin',
    onlineChanges: online.stream,
  );

  Future<void> goOffline() async {
    remote.offline = true;
    storage.offline = true;
    online.add(false);
    await Future<void>.delayed(Duration.zero);
  }

  void goOnline() {
    remote.offline = false;
    storage.offline = false;
    online.add(true);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    remote = FakeArchive();
    storage = FakeStorage();
    online = StreamController<bool>.broadcast();
  });

  test('the catalogue still loads offline from the device copy', () async {
    remote.rows['r1'] = const ArchiveRecord(id: 'r1', title: 'Birth register');
    final repo = build();
    await repo.watchAll().first; // loaded once online
    await goOffline();
    final List<ArchiveRecord> offline = await repo.watchAll().first;
    expect(offline.map((r) => r.title), <String>['Birth register']);
    repo.dispose();
  });

  test('offline with nothing cached is an error the screen can show', () async {
    remote.offline = true;
    final repo = build();
    await expectLater(repo.watchAll().first, throwsA(isA<NetworkFailure>()));
    repo.dispose();
  });

  test('records saved and submitted offline show at once and sync in order, '
      'uploading kept attachments first', () async {
    final repo = build();
    await goOffline();

    final StoredArchiveFile scan = await storage.uploadOrKeepForLater(
      recordId: 'r2',
      fileName: 'scan.jpg',
      bytes: Uint8List(1),
    );
    expect(scan.awaitingUpload, isTrue);
    await repo.upsertRecord(
      ArchiveRecord(
        id: 'r2',
        title: 'Land deed',
        files: <ArchiveFile>[
          ArchiveFile(url: scan.url, fileName: scan.fileName),
        ],
      ),
    );
    await repo.submitForReview('r2');
    expect(repo.isPending('r2'), isTrue);
    expect(repo.status.pending, 2);

    final List<ArchiveRecord> view = await repo.watchAll().first;
    expect(view.single.reviewStatus, ArchiveReviewStatus.pendingReview);

    goOnline();
    await repo.flush();
    expect(storage.uploaded, <String>['local/scan.jpg']);
    expect(remote.calls, <String>[
      'upsert r2 (https://cdn/scan.jpg)',
      'submit r2',
    ]);
    expect(repo.status.pending, 0);
    repo.dispose();
  });

  test('an upload that fails mid-sync is retried, not lost', () async {
    final repo = build();
    await goOffline();
    await repo.upsertRecord(
      const ArchiveRecord(
        id: 'r3',
        files: <ArchiveFile>[
          ArchiveFile(url: 'local/a.pdf', fileName: 'a.pdf'),
        ],
      ),
    );
    // Connectivity reports online but uploads still fail.
    remote.offline = false;
    await repo.flush();
    expect(repo.status.pending, 1);
    expect(remote.calls, isEmpty);

    storage.offline = false;
    await repo.flush();
    expect(remote.calls, <String>['upsert r3 (https://cdn/a.pdf)']);
    repo.dispose();
  });

  test('approve and delete made offline survive a restart', () async {
    remote.rows['r4'] = const ArchiveRecord(id: 'r4');
    remote.rows['r5'] = const ArchiveRecord(id: 'r5');
    final first = build();
    await first.watchAll().first;
    await goOffline();
    await first.review('r4', approved: true);
    await first.deleteRecord('r5');
    first.dispose();

    goOnline();
    final second = build();
    expect(second.status.pending, 2);
    await second.flush();
    expect(remote.calls, <String>['review r4 true', 'delete r5']);
    second.dispose();
  });
}

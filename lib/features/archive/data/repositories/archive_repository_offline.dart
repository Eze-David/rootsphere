import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/offline/offline_cache.dart';
import '../../../../core/offline/outbox.dart';
import '../../domain/entities/archive_record.dart';
import '../../domain/repositories/archive_repository.dart';
import '../services/archive_storage_service.dart';

/// Offline-first [ArchiveRepository] (the Digital Records Repository and the
/// Catalogue built from it), in front of the Supabase one.
///
/// Works like [TreeRepositoryOffline]: the last server list is kept on the
/// device, changes (save draft, submit, approve/reject, delete) apply to it
/// immediately and queue in an [Outbox] that replays them in order when the
/// network is back. Attachments added offline are kept on the device by
/// [ArchiveStorageService.uploadOrKeepForLater] and uploaded just before
/// their record syncs.
class ArchiveRepositoryOffline implements ArchiveRepository {
  ArchiveRepositoryOffline({
    required ArchiveRepository remote,
    required ArchiveStorageService storage,
    required SharedPreferences prefs,
    required OfflineCache cache,
    required String Function() currentUid,
    required Stream<bool> onlineChanges,
  }) : _remote = remote,
       _storage = storage,
       _cache = cache,
       _currentUid = currentUid {
    _outbox = Outbox(
      prefs: prefs,
      storageKey: 'offline_outbox_archive',
      currentUid: currentUid,
      send: _send,
      onDone: _onSynced,
      onlineChanges: onlineChanges,
      onReconnect: () {
        if (_sinks.isNotEmpty) _subscribe();
      },
    );
  }

  final ArchiveRepository _remote;
  final ArchiveStorageService _storage;
  final OfflineCache _cache;
  final String Function() _currentUid;
  late final Outbox _outbox;

  final Set<StreamController<List<ArchiveRecord>>> _sinks =
      <StreamController<List<ArchiveRecord>>>{};
  StreamSubscription<List<ArchiveRecord>>? _remoteSub;
  Timer? _retry;

  // ── Sync status ─────────────────────────────────────────────────────────

  SyncStatus get status => _outbox.status;

  Stream<SyncStatus> watchStatus() => _outbox.watchStatus();

  void clearError() => _outbox.clearError();

  Future<void> flush() => _outbox.flush();

  /// Whether a change to record [id] is still waiting to sync.
  bool isPending(String id) => _outbox.mine.any((op) => op.recordId == id);

  void dispose() {
    _outbox.dispose();
    _stop();
  }

  // ── Reads ────────────────────────────────────────────────────────────────

  @override
  Stream<List<ArchiveRecord>> watchAll() {
    late final StreamController<List<ArchiveRecord>> controller;
    controller = StreamController<List<ArchiveRecord>>(
      onListen: () {
        _sinks.add(controller);
        final List<ArchiveRecord>? local = _localView();
        if (local != null) controller.add(local);
        if (_remoteSub == null) _subscribe();
      },
      onCancel: () {
        _sinks.remove(controller);
        if (_sinks.isEmpty) _stop();
      },
    );
    return controller.stream;
  }

  void _subscribe() {
    _stop();
    _remoteSub = _remote.watchAll().listen(
      (List<ArchiveRecord> records) {
        _writeSnapshot(records);
        _emit();
      },
      onError: (Object e, StackTrace st) {
        unawaited(_remoteSub?.cancel());
        _remoteSub = null;
        if (_localView() == null) {
          final Object error = isNetworkError(e) ? const NetworkFailure() : e;
          for (final sink in _sinks) {
            sink.addError(error, st);
          }
        }
        _retry = Timer(OfflineCache.retryDelay, _subscribe);
      },
    );
  }

  void _stop() {
    _retry?.cancel();
    _retry = null;
    unawaited(_remoteSub?.cancel());
    _remoteSub = null;
  }

  void _emit() {
    final List<ArchiveRecord> view = _localView() ?? <ArchiveRecord>[];
    for (final sink in _sinks) {
      sink.add(view);
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  static const String _upsert = 'upsert';
  static const String _submit = 'submit';
  static const String _review = 'review';
  static const String _delete = 'delete';

  @override
  Future<void> upsertRecord(ArchiveRecord record) => _enqueue(
    _upsert,
    <String, dynamic>{'id': record.id, 'record': record.toJson()},
  );

  @override
  Future<void> submitForReview(String id) =>
      _enqueue(_submit, <String, dynamic>{'id': id});

  @override
  Future<void> review(String id, {required bool approved, String? note}) =>
      _enqueue(_review, <String, dynamic>{
        'id': id,
        'approved': approved,
        'note': note,
      });

  @override
  Future<void> deleteRecord(String id) =>
      _enqueue(_delete, <String, dynamic>{'id': id});

  Future<void> _enqueue(String type, Map<String, dynamic> data) async {
    final OutboxOp op = OutboxOp(type: type, data: data);
    _outbox.add(op);
    _emit();
    await _outbox.sendNow(op);
  }

  Future<void> _send(OutboxOp op) async {
    switch (op.type) {
      case _upsert:
        await _uploadKeptFiles(op);
        return _remote
            .upsertRecord(op.record!)
            .timeout(OfflineCache.requestTimeout);
      case _submit:
        return _remote
            .submitForReview(op.recordId)
            .timeout(OfflineCache.requestTimeout);
      case _review:
        return _remote
            .review(
              op.recordId,
              approved: op.data['approved'] as bool,
              note: op.data['note'] as String?,
            )
            .timeout(OfflineCache.requestTimeout);
      case _delete:
        return _remote
            .deleteRecord(op.recordId)
            .timeout(OfflineCache.requestTimeout);
    }
    // Unknown type (e.g. queued by a newer app version): drop it.
  }

  /// Uploads attachments that were added offline, one at a time, saving the
  /// queued record after each so a retry never uploads the same file twice.
  /// No timeout here: large scans and videos can legitimately take a while.
  Future<void> _uploadKeptFiles(OutboxOp op) async {
    ArchiveRecord record = op.record!;
    for (int i = 0; i < record.files.length; i++) {
      final ArchiveFile file = record.files[i];
      if (!_storage.isAwaitingUpload(file.url)) continue;
      final String url = await _storage.uploadKeptFile(
        recordId: record.id,
        fileName: file.fileName,
        path: file.url,
      );
      final List<ArchiveFile> files = List<ArchiveFile>.of(record.files);
      files[i] = ArchiveFile(
        url: url,
        fileName: file.fileName,
        kind: file.kind,
      );
      record = record.copyWith(files: files);
      op.data = <String, dynamic>{...op.data, 'record': record.toJson()};
      _outbox.update(op);
    }
  }

  /// Folds a synced op into the cached server list so the view doesn't
  /// briefly revert before the live stream catches up. A rejected op just
  /// disappears from the view.
  void _onSynced(OutboxOp op, {required bool synced}) {
    if (synced) {
      final List<ArchiveRecord>? snapshot = _readSnapshot();
      if (snapshot != null) _writeSnapshot(_apply(snapshot, <OutboxOp>[op]));
    }
    _emit();
  }

  // ── Local state ──────────────────────────────────────────────────────────

  /// Server list + this user's queued changes, or null if the list has never
  /// been loaded on this device.
  List<ArchiveRecord>? _localView() {
    final List<ArchiveRecord>? snapshot = _readSnapshot();
    final List<OutboxOp> pending = _outbox.mine;
    if (snapshot == null && pending.isEmpty) return null;
    return _apply(snapshot ?? <ArchiveRecord>[], pending);
  }

  // Per account: admins see every record, everyone else only published ones.
  String get _snapshotKey => 'archive_records_${_currentUid()}';

  List<ArchiveRecord>? _readSnapshot() => _cache.read(
    _snapshotKey,
    (json) => (json! as List<dynamic>)
        .map((e) => ArchiveRecord.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  void _writeSnapshot(List<ArchiveRecord> records) =>
      _cache.write(_snapshotKey, records.map((r) => r.toJson()).toList());

  /// Applies [ops] to [base] the same way the server would — mirrors
  /// [ArchiveRepositorySupabase]. New records go first (newest first).
  static List<ArchiveRecord> _apply(
    List<ArchiveRecord> base,
    Iterable<OutboxOp> ops,
  ) {
    final List<ArchiveRecord> records = List<ArchiveRecord>.of(base);
    for (final OutboxOp op in ops) {
      final int i = records.indexWhere((r) => r.id == op.recordId);
      switch (op.type) {
        case _upsert:
          final ArchiveRecord record = op.record!;
          if (i >= 0) {
            records[i] = record;
          } else {
            records.insert(0, record);
          }
        case _submit:
          if (i >= 0) {
            records[i] = records[i].copyWith(
              reviewStatus: ArchiveReviewStatus.pendingReview,
            );
          }
        case _review:
          if (i >= 0) {
            final bool approved = op.data['approved'] as bool;
            records[i] = records[i].copyWith(
              reviewStatus: approved
                  ? ArchiveReviewStatus.published
                  : ArchiveReviewStatus.rejected,
              reviewerNote: op.data['note'] as String?,
            );
          }
        case _delete:
          if (i >= 0) records.removeAt(i);
      }
    }
    return records;
  }
}

/// Typed access to an archive op's [OutboxOp.data].
extension on OutboxOp {
  String get recordId => data['id'] as String;
  ArchiveRecord? get record => data['record'] == null
      ? null
      : ArchiveRecord.fromJson(
          Map<String, dynamic>.from(data['record'] as Map),
        );
}

import '../../../../core/offline/offline_cache.dart';
import '../../domain/entities/record.dart';
import '../../domain/repositories/record_repository.dart';

/// [RecordRepository] that keeps showing a tree's last-loaded records when
/// offline. Adding or deleting records still needs the network (attachments
/// have to upload anyway) and goes straight to [_remote].
class RecordRepositoryOffline implements RecordRepository {
  RecordRepositoryOffline({
    required RecordRepository remote,
    required OfflineCache cache,
    required String Function() currentUid,
    required Stream<bool> Function() onlineChanges,
  }) : _remote = remote,
       _cache = cache,
       _currentUid = currentUid,
       _onlineChanges = onlineChanges;

  final RecordRepository _remote;
  final OfflineCache _cache;
  final String Function() _currentUid;
  final Stream<bool> Function() _onlineChanges;

  static Object? _encode(List<Record> records) =>
      records.map((r) => r.toJson()).toList();

  static List<Record> _decode(Object? json) => (json! as List<dynamic>)
      .map((e) => Record.fromJson(e as Map<String, dynamic>))
      .toList();

  @override
  Stream<List<Record>> watchRecords(String treeId) =>
      _cache.stream<List<Record>>(
        key: 'records_$treeId',
        remote: () => _remote.watchRecords(treeId),
        encode: _encode,
        decode: _decode,
        onlineChanges: _onlineChanges(),
      );

  @override
  Stream<List<Record>> watchAllRecords() => _cache.stream<List<Record>>(
    key: 'all_records_${_currentUid()}',
    remote: _remote.watchAllRecords,
    encode: _encode,
    decode: _decode,
    onlineChanges: _onlineChanges(),
  );

  @override
  Future<List<Record>> getRecords(String treeId) => _cache.future<List<Record>>(
    key: 'records_$treeId',
    remote: () => _remote.getRecords(treeId),
    encode: _encode,
    decode: _decode,
  );

  @override
  Future<void> upsertRecord(Record record) => _remote.upsertRecord(record);

  @override
  Future<void> deleteRecord(String treeId, String id) =>
      _remote.deleteRecord(treeId, id);
}

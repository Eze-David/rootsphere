import '../../../../core/offline/offline_cache.dart';
import '../../domain/entities/family_tree.dart';
import '../../domain/repositories/family_tree_repository.dart';

/// [FamilyTreeRepository] that keeps showing the last-loaded trees list and
/// "this is me" link when offline. Changes (create/join/rename…) still need
/// the network and go straight to [_remote].
class FamilyTreeRepositoryOffline implements FamilyTreeRepository {
  FamilyTreeRepositoryOffline({
    required FamilyTreeRepository remote,
    required OfflineCache cache,
    required String Function() currentUid,
    required Stream<bool> Function() onlineChanges,
  }) : _remote = remote,
       _cache = cache,
       _currentUid = currentUid,
       _onlineChanges = onlineChanges;

  final FamilyTreeRepository _remote;
  final OfflineCache _cache;
  final String Function() _currentUid;
  final Stream<bool> Function() _onlineChanges;

  @override
  Future<List<FamilyTree>> getTrees() => _cache.future<List<FamilyTree>>(
    key: 'my_trees_${_currentUid()}',
    remote: _remote.getTrees,
    encode: (trees) => trees
        .map(
          (t) => <String, dynamic>{
            'id': t.id,
            'name': t.name,
            'role': t.role.name,
            'memberCount': t.memberCount,
          },
        )
        .toList(),
    decode: (json) => (json! as List<dynamic>).map((e) {
      final Map<String, dynamic> m = e as Map<String, dynamic>;
      return FamilyTree(
        id: m['id'] as String,
        name: m['name'] as String,
        role: TreeRole.values.byName(m['role'] as String),
        memberCount: m['memberCount'] as int? ?? 0,
      );
    }).toList(),
  );

  @override
  Stream<String?> watchMyPersonId(String treeId) => _cache.stream<String?>(
    key: 'my_person_${_currentUid()}_$treeId',
    remote: () => _remote.watchMyPersonId(treeId),
    encode: (id) => id,
    decode: (json) => json as String?,
    onlineChanges: _onlineChanges(),
  );

  @override
  Future<FamilyTree> createTree(String name) => _remote.createTree(name);

  @override
  Future<FamilyTree> joinTree(String id, {String fallbackName = ''}) =>
      _remote.joinTree(id, fallbackName: fallbackName);

  @override
  Future<void> unlinkTree(String id) => _remote.unlinkTree(id);

  @override
  Future<FamilyTree> renameTree(String id, String name) =>
      _remote.renameTree(id, name);

  @override
  Future<void> setMyPersonId(String treeId, String personId) =>
      _remote.setMyPersonId(treeId, personId);
}

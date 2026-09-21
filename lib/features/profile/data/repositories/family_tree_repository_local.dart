import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/family_tree.dart';
import '../../domain/repositories/family_tree_repository.dart';

/// SharedPreferences-backed [FamilyTreeRepository] used when Supabase is not
/// configured (e.g. a fresh clone). Trees are stored as a JSON list; joining
/// simply records the supplied id/name without any server validation.
class FamilyTreeRepositoryLocal implements FamilyTreeRepository {
  FamilyTreeRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;
  final StreamController<Map<String, String>> _meController =
      StreamController<Map<String, String>>.broadcast();

  static const String _kTrees = 'profile_linked_trees';
  static const String _kMe = 'profile_tree_me_v1';

  Map<String, String> _readMe() {
    final String? raw = _prefs.getString(_kMe);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, String>{};
    }
  }

  List<FamilyTree> _read() {
    final String? raw = _prefs.getString(_kTrees);
    if (raw == null || raw.isEmpty) return <FamilyTree>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return <FamilyTree>[];
    }
  }

  Future<void> _write(List<FamilyTree> trees) async {
    await _prefs.setString(_kTrees, jsonEncode(trees.map(_toJson).toList()));
  }

  @override
  Future<List<FamilyTree>> getTrees() async => _read();

  @override
  Future<FamilyTree> createTree(String name) async {
    final tree = FamilyTree(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      role: TreeRole.owner,
      memberCount: 1,
    );
    await _write(<FamilyTree>[..._read(), tree]);
    return tree;
  }

  @override
  Future<FamilyTree> joinTree(String id, {String fallbackName = ''}) async {
    final trees = _read();
    for (final t in trees) {
      if (t.id == id) return t;
    }
    final tree = FamilyTree(
      id: id,
      name: fallbackName.isEmpty ? 'Untitled tree' : fallbackName,
      role: TreeRole.viewer,
      memberCount: 0,
    );
    await _write(<FamilyTree>[...trees, tree]);
    return tree;
  }

  @override
  Future<void> unlinkTree(String id) async {
    await _write(_read().where((t) => t.id != id).toList());
  }

  @override
  Future<FamilyTree> renameTree(String id, String name) async {
    final trees = _read();
    final index = trees.indexWhere((t) => t.id == id);
    if (index == -1) {
      throw Exception('Tree not found.');
    }
    if (trees[index].role != TreeRole.owner) {
      throw Exception('Only the tree owner can rename it.');
    }
    final updated = FamilyTree(
      id: trees[index].id,
      name: name,
      role: trees[index].role,
      memberCount: trees[index].memberCount,
    );
    trees[index] = updated;
    await _write(trees);
    return updated;
  }

  @override
  Stream<String?> watchMyPersonId(String treeId) {
    scheduleMicrotask(() => _meController.add(_readMe()));
    return _meController.stream.map((map) => map[treeId]);
  }

  @override
  Future<void> setMyPersonId(String treeId, String personId) async {
    final Map<String, String> me = _readMe()..[treeId] = personId;
    await _prefs.setString(_kMe, jsonEncode(me));
    _meController.add(me);
  }

  static FamilyTree _fromJson(Map<String, dynamic> json) {
    return FamilyTree(
      id: json['id'] as String,
      name: json['name'] as String,
      role: TreeRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => TreeRole.viewer,
      ),
      memberCount: json['memberCount'] as int? ?? 0,
    );
  }

  static Map<String, dynamic> _toJson(FamilyTree tree) {
    return <String, dynamic>{
      'id': tree.id,
      'name': tree.name,
      'role': tree.role.name,
      'memberCount': tree.memberCount,
    };
  }
}

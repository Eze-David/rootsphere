import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_provider.dart';
import '../../domain/entities/family_tree.dart';

/// Stub controller that stores linked trees locally in SharedPreferences.
///
/// In Phase 2 this will be replaced by a real repository backed by Supabase.
class FamilyTreeController extends Notifier<List<FamilyTree>> {
  static const String _kTrees = 'profile_linked_trees';

  dynamic get _prefs => ref.read(sharedPreferencesProvider);

  List<FamilyTree> _readTrees() {
    final String? raw = _prefs.getString(_kTrees);
    if (raw == null || raw.isEmpty) return const <FamilyTree>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const <FamilyTree>[];
    }
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

  Future<void> _persist() async {
    final String encoded = jsonEncode(state.map(_toJson).toList());
    await _prefs.setString(_kTrees, encoded);
  }

  @override
  List<FamilyTree> build() => _readTrees();

  Future<void> createTree(String name) async {
    final tree = FamilyTree(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      role: TreeRole.owner,
      memberCount: 1,
    );
    state = [...state, tree];
    await _persist();
  }

  Future<void> joinTree(String id, String name) async {
    if (state.any((t) => t.id == id)) return;
    final tree = FamilyTree(
      id: id,
      name: name.isEmpty ? 'Untitled tree' : name,
      role: TreeRole.viewer,
      memberCount: 0,
    );
    state = [...state, tree];
    await _persist();
  }

  Future<void> unlinkTree(String id) async {
    state = state.where((t) => t.id != id).toList();
    await _persist();
  }
}

final familyTreeControllerProvider =
    NotifierProvider<FamilyTreeController, List<FamilyTree>>(
      FamilyTreeController.new,
    );

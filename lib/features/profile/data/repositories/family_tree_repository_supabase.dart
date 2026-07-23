import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/family_tree.dart';
import '../../domain/repositories/family_tree_repository.dart';

/// Supabase-backed [FamilyTreeRepository].
///
/// Linked trees are read via the `my_trees` RPC; joining goes through the
/// `join_tree` RPC, which validates the id server-side and records membership
/// in `tree_members` (see migration 20260617000000_tree_members.sql).
class FamilyTreeRepositorySupabase implements FamilyTreeRepository {
  FamilyTreeRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _trees => _client.from('trees');
  SupabaseQueryBuilder get _members => _client.from('tree_members');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Future<List<FamilyTree>> getTrees() async {
    try {
      final List<dynamic> rows = await _client.rpc('my_trees') as List<dynamic>;
      return rows
          .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<FamilyTree> createTree(String name) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    final String id = 't_${DateTime.now().millisecondsSinceEpoch}';
    try {
      // The trees insert trigger enrols the owner into tree_members.
      final Map<String, dynamic> row = await _trees
          .insert(<String, dynamic>{'id': id, 'name': name, 'owner_id': _uid})
          .select()
          .single();
      return FamilyTree(
        id: row['id'] as String,
        name: row['name'] as String? ?? name,
        role: TreeRole.owner,
        memberCount: 1,
      );
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<FamilyTree> joinTree(String id, {String fallbackName = ''}) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final dynamic result = await _client.rpc(
        'join_tree',
        params: <String, dynamic>{'p_tree_id': id},
      );
      final Map<String, dynamic> row = Map<String, dynamic>.from(result as Map);
      final int memberCount = await _memberCount(id);
      return FamilyTree(
        id: row['id'] as String,
        name: row['name'] as String? ?? 'Untitled tree',
        role: TreeRole.viewer,
        memberCount: memberCount,
      );
    } on PostgrestException catch (e) {
      if (_isNotFound(e)) {
        throw const ServerFailure('No family tree found with that ID.');
      }
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> unlinkTree(String id) async {
    try {
      await _members.delete().eq('tree_id', id).eq('user_id', _uid);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<FamilyTree> renameTree(String id, String name) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _trees
          .update(<String, dynamic>{'name': name})
          .eq('id', id)
          .eq('owner_id', _uid)
          .select()
          .single();
      final int memberCount = await _memberCount(id);
      return FamilyTree(
        id: row['id'] as String,
        name: row['name'] as String? ?? name,
        role: TreeRole.owner,
        memberCount: memberCount,
      );
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  Future<int> _memberCount(String treeId) async {
    try {
      final List<dynamic> rows = await _members
          .select('user_id')
          .eq('tree_id', treeId);
      return rows.length;
    } on PostgrestException {
      return 0;
    }
  }

  bool _isNotFound(PostgrestException e) {
    final String code = e.code ?? '';
    return code == 'no_data_found' ||
        code == 'P0002' ||
        e.message.toLowerCase().contains('not found');
  }

  FamilyTree _fromRow(Map<String, dynamic> row) {
    return FamilyTree(
      id: row['id'] as String,
      name: row['name'] as String? ?? 'Untitled tree',
      role: TreeRole.values.firstWhere(
        (r) => r.name == row['role'],
        orElse: () => TreeRole.viewer,
      ),
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
    );
  }
}

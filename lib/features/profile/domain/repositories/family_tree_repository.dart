import '../entities/family_tree.dart';

/// Persistence contract for the family trees a user is linked to.
///
/// Backed by Supabase (`tree_members` + RPCs) when configured, or local
/// SharedPreferences otherwise — the presentation layer is unaware which.
abstract class FamilyTreeRepository {
  /// All trees the current user belongs to.
  Future<List<FamilyTree>> getTrees();

  /// Creates a new tree owned by the current user and links them to it.
  Future<FamilyTree> createTree(String name);

  /// Joins an existing tree by [id]. Throws a [Failure] when no tree with that
  /// id exists. [fallbackName] is only used by the local implementation, which
  /// has no server to resolve the real name from.
  Future<FamilyTree> joinTree(String id, {String fallbackName = ''});

  /// Removes the current user's link to the tree with [id] (leave / unlink).
  Future<void> unlinkTree(String id);

  /// Renames the tree with [id] to [name]. Only owners can rename.
  Future<FamilyTree> renameTree(String id, String name);
}

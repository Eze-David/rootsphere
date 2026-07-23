import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/family_tree_repository_local.dart';
import '../../data/repositories/family_tree_repository_supabase.dart';
import '../../domain/entities/family_tree.dart';
import '../../domain/repositories/family_tree_repository.dart';

/// Family-tree linking repository: Supabase-backed when configured, local
/// SharedPreferences otherwise. The interface is identical either way.
final familyTreeRepositoryProvider = Provider<FamilyTreeRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return FamilyTreeRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return FamilyTreeRepositoryLocal(prefs);
});

/// Loads and mutates the list of trees the signed-in user is linked to.
class FamilyTreeController extends AsyncNotifier<List<FamilyTree>> {
  FamilyTreeRepository get _repo => ref.read(familyTreeRepositoryProvider);

  @override
  Future<List<FamilyTree>> build() {
    // Must watch the reactive auth stream, not just read the repository —
    // otherwise this AsyncNotifier's result is computed once for whichever
    // account is signed in first and cached for the rest of the app
    // session, so a different account signing in later would keep seeing
    // the previous account's linked trees on the Profile screen.
    ref.watch(authStateProvider);
    return _repo.getTrees();
  }

  Future<void> _refresh() async {
    state = AsyncValue<List<FamilyTree>>.data(await _repo.getTrees());
  }

  /// Creates a tree and refreshes the list. Rethrows on failure so the caller
  /// (dialog) can surface the error.
  Future<FamilyTree> createTree(String name) async {
    final tree = await _repo.createTree(name);
    await _refresh();
    return tree;
  }

  /// Joins a tree by id and refreshes the list. Throws when the id is invalid.
  Future<FamilyTree> joinTree(String id, {String fallbackName = ''}) async {
    final tree = await _repo.joinTree(id, fallbackName: fallbackName);
    await _refresh();
    return tree;
  }

  Future<void> unlinkTree(String id) async {
    await _repo.unlinkTree(id);
    await _refresh();
  }

  Future<FamilyTree> renameTree(String id, String name) async {
    final tree = await _repo.renameTree(id, name);
    await _refresh();
    return tree;
  }
}

final familyTreeControllerProvider =
    AsyncNotifierProvider<FamilyTreeController, List<FamilyTree>>(
      FamilyTreeController.new,
    );

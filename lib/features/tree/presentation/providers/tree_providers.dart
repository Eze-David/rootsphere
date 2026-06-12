import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../data/repositories/tree_repository_local.dart';
import '../../data/repositories/tree_repository_supabase.dart';
import '../../data/services/photo_storage_service.dart';
import '../../domain/entities/person.dart';
import '../../domain/repositories/tree_repository.dart';
import '../layout/tree_layout.dart';

/// Tree repository: Supabase-backed when configured, local JSON otherwise.
/// The interface is identical, so the rest of the app is unaware which is used.
final treeRepositoryProvider = Provider<TreeRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return TreeRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return TreeRepositoryLocal(prefs);
});

/// Photo upload/storage service (Supabase Storage + local fallback).
final photoStorageServiceProvider = Provider<PhotoStorageService>((ref) {
  return PhotoStorageService();
});

/// Explicit tree override set by the UI (null = use [activeTreeIdProvider]'s
/// default). Kept nullable so the default can depend on auth state.
final selectedTreeIdProvider = StateProvider<String?>((ref) => null);

/// The tree currently in use.
///
/// Resolution order:
///  1. an explicit selection from the UI;
///  2. the signed-in user's personal tree (`t_<uid>`) when Supabase is ready;
///  3. the local demo tree (`okonkwo`).
final activeTreeIdProvider = Provider<String>((ref) {
  final explicit = ref.watch(selectedTreeIdProvider);
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (SupabaseConfig.isReady) {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) return 't_$uid';
  }
  return 'okonkwo';
});

/// The person the view is centred on. Null until persons load (then defaults
/// to a sensible root).
final focusPersonIdProvider = StateProvider<String?>((ref) => null);

/// Which layout the renderer should produce.
final treeModeProvider = StateProvider<TreeMode>((ref) => TreeMode.descendants);

/// Streams all persons in the active tree.
final personsProvider = StreamProvider<List<Person>>((ref) {
  final repo = ref.watch(treeRepositoryProvider);
  final treeId = ref.watch(activeTreeIdProvider);
  return repo.watchPersons(treeId);
});

/// Convenience: persons keyed by id.
final personMapProvider = Provider<Map<String, Person>>((ref) {
  final persons = ref.watch(personsProvider).value ?? const <Person>[];
  return <String, Person>{for (final p in persons) p.id: p};
});

/// Single person lookup.
final personByIdProvider = Provider.family<Person?, String>((ref, id) {
  return ref.watch(personMapProvider)[id];
});

/// The resolved focus id — falls back to the first root (a person with no
/// parents) when nothing is explicitly selected.
final resolvedFocusIdProvider = Provider<String?>((ref) {
  final explicit = ref.watch(focusPersonIdProvider);
  final persons = ref.watch(personsProvider).value ?? const <Person>[];
  if (persons.isEmpty) return null;
  if (explicit != null && persons.any((p) => p.id == explicit)) {
    return explicit;
  }
  // Prefer the deepest descendant root candidate; otherwise the first person.
  final withParents = persons.where((p) => p.parentIds.isNotEmpty).toList();
  if (withParents.isNotEmpty) return withParents.last.id;
  return persons.first.id;
});

/// The computed layout for the current persons / focus / mode.
final treeLayoutProvider = Provider<TreeLayout?>((ref) {
  final persons = ref.watch(personsProvider).value;
  if (persons == null || persons.isEmpty) return null;
  final focusId = ref.watch(resolvedFocusIdProvider);
  if (focusId == null) return null;
  final mode = ref.watch(treeModeProvider);
  return TreeLayoutEngine.build(
    persons: persons,
    focusId: focusId,
    mode: mode,
  );
});

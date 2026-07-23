import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/tree_repository_local.dart';
import '../../data/repositories/tree_repository_supabase.dart';
import '../../data/services/geocoding_service.dart';
import '../../data/services/photo_storage_service.dart';
import '../../domain/entities/edit_history_entry.dart';
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

/// Place-name → coordinates lookup (Supabase Edge Function, cached).
final geocodingServiceProvider =
    Provider<GeocodingService>((ref) => GeocodingService());

/// Resolved coordinates for a person's location string, cached while a
/// screen has it in view so rebuilds don't re-geocode. `autoDispose` (rather
/// than a session-long cache) matters here specifically for transient
/// failures: [GeocodingService.geocode] throws instead of returning null for
/// those, so a bad network moment doesn't get permanently mistaken for "no
/// coordinates for this place" — leaving and reopening the map/profile
/// retries instead of staying pin-less for the rest of the session. A
/// genuine not-found result (null, no throw) still just falls back to a
/// plain placeholder.
final geocodeProvider =
    FutureProvider.autoDispose.family<GeocodeResult?, String>((
  ref,
  location,
) {
  return ref.watch(geocodingServiceProvider).geocode(location);
});

const String _selectedTreeIdPrefsKey = 'selected_tree_id';

/// Explicit tree override set by the UI (null = use [activeTreeIdProvider]'s
/// default). Kept nullable so the default can depend on auth state.
///
/// Restored from disk on startup and persisted by [setSelectedTreeId] —
/// without this, a hot restart (or relaunch) silently drops back to the
/// default resolution, and anything added afterward lands in the wrong tree.
final selectedTreeIdProvider = StateProvider<String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final String? stored = prefs.getString(_selectedTreeIdPrefsKey);
  return (stored == null || stored.isEmpty) ? null : stored;
});

/// Sets the active tree override and persists it so it survives restarts.
/// Pass `null` to clear the override (falls back to [activeTreeIdProvider]'s
/// default resolution).
void setSelectedTreeId(WidgetRef ref, String? treeId) {
  ref.read(selectedTreeIdProvider.notifier).state = treeId;
  final prefs = ref.read(sharedPreferencesProvider);
  if (treeId == null || treeId.isEmpty) {
    prefs.remove(_selectedTreeIdPrefsKey);
  } else {
    prefs.setString(_selectedTreeIdPrefsKey, treeId);
  }
}

/// Clears the explicit tree override — called on sign-out, since this is
/// persisted globally on the device rather than per-account. Without this, a
/// user who'd explicitly switched trees (via the "Family Trees" list) and
/// then signed out would have the *next* signed-in account on this device
/// inherit that same explicit tree, instead of resolving to that account's
/// own. Takes the plain [Ref] (not [WidgetRef]) so it's callable from
/// [AuthController], which only has the former.
void clearSelectedTreeId(Ref ref) {
  ref.read(selectedTreeIdProvider.notifier).state = null;
  ref.read(sharedPreferencesProvider).remove(_selectedTreeIdPrefsKey);
}

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
    // Must go through the watched auth stream, not a direct
    // `SupabaseConfig.client.auth.currentUser` read — that bypasses
    // Riverpod's dependency graph entirely, so this provider would compute
    // once, cache the first signed-in user's tree id, and never
    // re-evaluate: logging out and into a *different* account would keep
    // showing the previous account's tree for the rest of the app session.
    final uid = ref.watch(authStateProvider).value?.id;
    if (uid != null && uid.isNotEmpty) return 't_$uid';
  }
  return 'okonkwo';
});

/// The person the view is centred on. Null until persons load (then defaults
/// to a sensible root, or the last-viewed person for this tree — see
/// [resolvedFocusIdProvider] and [setFocusPerson]).
final focusPersonIdProvider = StateProvider<String?>((ref) => null);

String _lastFocusPrefsKey(String treeId) => 'tree_last_focus_$treeId';

/// Sets the tree's focus person and remembers it (per tree id) so switching
/// away and back — e.g. via the Family Trees list — returns to the same
/// person instead of falling back to a generic heuristic. Pass `null` to
/// defer to that heuristic without changing what's remembered.
void setFocusPerson(WidgetRef ref, String? personId) {
  ref.read(focusPersonIdProvider.notifier).state = personId;
  if (personId == null || personId.isEmpty) return;
  final String treeId = ref.read(activeTreeIdProvider);
  ref.read(sharedPreferencesProvider).setString(_lastFocusPrefsKey(treeId), personId);
}

/// Which layout the renderer should produce. The redesigned ancestor pedigree
/// (focus at the bottom, ancestors + "Add parent" slots growing upward) is the
/// default view.
final treeModeProvider = StateProvider<TreeMode>((ref) => TreeMode.ancestors);

/// Ids of people whose ancestors are currently collapsed (hidden) in the
/// kinship view. Toggled by the chevrons on the tree.
final collapsedAncestorsProvider =
    StateProvider<Set<String>>((ref) => <String>{});

/// Whether the ancestor pedigree grows upward (vertical) or rightward
/// (horizontal). Chosen from the app-bar "view" control.
final treeOrientationProvider =
    StateProvider<TreeOrientation>((ref) => TreeOrientation.vertical);

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

/// Edit history (audit log) for a given person, newest first.
final personEditHistoryProvider =
    FutureProvider.family<List<EditHistoryEntry>, String>((ref, personId) async {
  // Rebuild when the person changes so a fresh edit shows immediately.
  ref.watch(personByIdProvider(personId));
  final repo = ref.watch(treeRepositoryProvider);
  return repo.getEditHistory(personId);
});

/// Recent person activity (additions + edits) across the whole active tree,
/// newest first — powers the dashboard's Recent Activity feed.
final recentTreeActivityProvider =
    FutureProvider<List<EditHistoryEntry>>((ref) async {
  // Rebuild whenever the tree's people change (e.g. right after someone new
  // is added) so the feed doesn't need a manual refresh.
  ref.watch(personsProvider);
  final repo = ref.watch(treeRepositoryProvider);
  final String treeId = ref.watch(activeTreeIdProvider);
  return repo.getRecentEditHistory(treeId);
});

/// The resolved focus id.
///
/// Resolution order: an explicit in-session selection; the last person this
/// tree was focused on (persisted by [setFocusPerson], so re-selecting a tree
/// from the Family Trees list returns to where you left off instead of an
/// arbitrary heuristic pick); otherwise the first root-ish candidate.
final resolvedFocusIdProvider = Provider<String?>((ref) {
  final explicit = ref.watch(focusPersonIdProvider);
  final persons = ref.watch(personsProvider).value ?? const <Person>[];
  if (persons.isEmpty) return null;
  if (explicit != null && persons.any((p) => p.id == explicit)) {
    return explicit;
  }

  final String treeId = ref.watch(activeTreeIdProvider);
  final String? remembered =
      ref.watch(sharedPreferencesProvider).getString(_lastFocusPrefsKey(treeId));
  if (remembered != null && persons.any((p) => p.id == remembered)) {
    return remembered;
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
  final collapsed = ref.watch(collapsedAncestorsProvider);
  final orientation = ref.watch(treeOrientationProvider);
  return TreeLayoutEngine.build(
    persons: persons,
    focusId: focusId,
    mode: mode,
    collapsed: collapsed,
    orientation: orientation,
  );
});

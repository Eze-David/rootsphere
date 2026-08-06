import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../collab/domain/entities/opportunity.dart';
import '../../../collab/domain/entities/role_verification.dart';
import '../../../collab/presentation/providers/role_verification_providers.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../data/repositories/record_repository_local.dart';
import '../../data/repositories/record_repository_supabase.dart';
import '../../data/services/global_people_service.dart';
import '../../data/services/global_records_service.dart';
import '../../data/services/historical_records_service.dart';
import '../../data/services/ocr_service.dart';
import '../../data/services/record_storage_service.dart';
import '../../domain/entities/global_person_match.dart';
import '../../domain/entities/global_record_match.dart';
import '../../domain/entities/historical_record.dart';
import '../../domain/entities/record.dart';
import '../../domain/repositories/record_repository.dart';

/// Record repository: Supabase-backed when configured, local JSON otherwise.
final recordRepositoryProvider = Provider<RecordRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return RecordRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return RecordRepositoryLocal(prefs);
});

/// Storage service for record attachments (Supabase Storage + local fallback).
final recordStorageServiceProvider = Provider<RecordStorageService>((ref) {
  return RecordStorageService();
});

/// Cross-platform OCR (Supabase Edge Function).
final ocrServiceProvider = Provider<OcrService>((ref) => OcrService());

/// External historical-records search (FamilySearch via Supabase Edge Function).
final historicalRecordsServiceProvider = Provider<HistoricalRecordsService>(
  (ref) => HistoricalRecordsService(),
);

/// Global cross-tree people search (privacy-safe RPC).
final globalPeopleServiceProvider = Provider<GlobalPeopleService>(
  (ref) => GlobalPeopleService(),
);

/// Global cross-tree search for unattached records (privacy-safe RPC).
final globalRecordsServiceProvider = Provider<GlobalRecordsService>(
  (ref) => GlobalRecordsService(),
);

/// Whether the signed-in user is an admin or an approved Finder/Indexer —
/// same roles that already unlock the review queues under `/admin/*` (see
/// opportunity_actions.dart) — and so should see records across every tree,
/// not just their own, when browsing the Records library.
final canSeeAllRecordsProvider = Provider<bool>((ref) {
  final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;
  if (isAdmin) return true;
  final RoleVerification? finder = ref.watch(
    myVerificationForRoleProvider(CollaborationRole.finder),
  );
  final RoleVerification? indexer = ref.watch(
    myVerificationForRoleProvider(CollaborationRole.indexer),
  );
  return finder?.status == VerificationStatus.approved ||
      indexer?.status == VerificationStatus.approved;
});

/// Streams the records the signed-in user should see: everyone's, across
/// every tree, for admins/approved Finders/Indexers (see
/// [canSeeAllRecordsProvider]); just the active tree's otherwise.
final recordsProvider = StreamProvider<List<Record>>((ref) {
  final repo = ref.watch(recordRepositoryProvider);
  if (ref.watch(canSeeAllRecordsProvider)) {
    return repo.watchAllRecords();
  }
  final treeId = ref.watch(activeTreeIdProvider);
  return repo.watchRecords(treeId);
});

/// Free-text search query for the records library.
final recordSearchProvider = StateProvider<String>((ref) => '');

/// Active type filter (null = "All").
final recordTypeFilterProvider = StateProvider<RecordType?>((ref) => null);

/// Records after applying the search query and type filter, used by the list.
final filteredRecordsProvider = Provider<List<Record>>((ref) {
  final List<Record> all = ref.watch(recordsProvider).value ?? const <Record>[];
  final String query = ref.watch(recordSearchProvider).trim().toLowerCase();
  final RecordType? type = ref.watch(recordTypeFilterProvider);
  final Map<String, Person> people = ref.watch(personMapProvider);

  return all.where((r) {
    if (type != null && r.type != type) return false;
    if (query.isEmpty) return true;
    final String haystack = <String>[
      r.title,
      r.repository,
      r.type.label,
      r.notes ?? '',
      r.ocrText ?? '',
      if (r.year != null) '${r.year}',
      // Linked people's names so a record is findable by who it's about.
      for (final id in r.personIds) people[id]?.fullName ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }).toList();
});

/// Community (cross-tree, unattached) records matching the same free-text
/// search box on the "All records" screen — the same source (and the same
/// title/repository/OCR-text matching) the per-category search screens use
/// for their "COMMUNITY RECORDS" section, so the main library search reaches
/// just as far, not only the signed-in user's own visible records.
final communityRecordSearchProvider = FutureProvider.family<
  List<GlobalRecordMatch>,
  String
>((ref, query) async {
  final String q = query.trim();
  if (q.isEmpty) return const <GlobalRecordMatch>[];
  return ref
      .read(globalRecordsServiceProvider)
      .search(RecordSearchQuery(firstName: q));
});

/// Cross-tree people matching the same free-text search box, via the OR-based
/// `search_persons_global_freetext` RPC (see [GlobalPeopleService.searchFreeText])
/// rather than the structured first/last/place form the per-category search
/// screens use.
final communityPeopleSearchProvider =
    FutureProvider.family<List<GlobalPersonMatch>, String>((ref, query) async {
      final String q = query.trim();
      if (q.isEmpty) return const <GlobalPersonMatch>[];
      return ref.read(globalPeopleServiceProvider).searchFreeText(q);
    });

/// External (FamilySearch-style) historical records matching the same
/// free-text search box. That provider expects a real first/last name pair,
/// so the single search term is split heuristically — see
/// [splitFreeTextName] — rather than crammed whole into one field.
final externalRecordSearchProvider =
    FutureProvider.family<RecordSearchResult, String>((ref, query) async {
      final String q = query.trim();
      if (q.isEmpty) return const RecordSearchResult();
      final (String first, String last, int? year) = splitFreeTextName(q);
      return ref
          .read(historicalRecordsServiceProvider)
          .search(
            RecordSearchQuery(firstName: first, lastName: last, year: year),
          );
    });

/// Splits a single free-text search term into a first/last name pair (plus
/// a standalone 4-digit year, if present) for providers that expect
/// structured name fields — e.g. "John Smith 1920" → ("John", "Smith", 1920).
/// A single word is treated as a first name only.
(String, String, int?) splitFreeTextName(String query) {
  final List<String> tokens = query
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  int? year;
  final List<String> nameTokens = <String>[];
  for (final String t in tokens) {
    final int? y = int.tryParse(t);
    if (year == null && y != null && t.length == 4) {
      year = y;
    } else {
      nameTokens.add(t);
    }
  }
  if (nameTokens.isEmpty) return ('', '', year);
  if (nameTokens.length == 1) return (nameTokens.first, '', year);
  return (nameTokens.first, nameTokens.sublist(1).join(' '), year);
}

/// Single record lookup by id (from the active tree's stream).
final recordByIdProvider = Provider.family<Record?, String>((ref, id) {
  final List<Record> all = ref.watch(recordsProvider).value ?? const <Record>[];
  for (final r in all) {
    if (r.id == id) return r;
  }
  return null;
});

/// Records that cite a given person, used by the AI Research Assistant.
final recordsForPersonProvider = Provider.family<List<Record>, String>((
  ref,
  personId,
) {
  final List<Record> all = ref.watch(recordsProvider).value ?? const <Record>[];
  return all.where((r) => r.personIds.contains(personId)).toList();
});

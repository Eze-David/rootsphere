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

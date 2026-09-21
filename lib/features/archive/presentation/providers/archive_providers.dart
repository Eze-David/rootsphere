import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../records/domain/entities/record.dart';
import '../../data/repositories/archive_access_request_repository_local.dart';
import '../../data/repositories/archive_access_request_repository_supabase.dart';
import '../../data/repositories/archive_repository_local.dart';
import '../../data/repositories/archive_repository_supabase.dart';
import '../../data/repositories/saved_archive_records_repository_local.dart';
import '../../data/repositories/saved_archive_records_repository_supabase.dart';
import '../../data/services/archive_storage_service.dart';
import '../../domain/entities/archive_access_request.dart';
import '../../domain/entities/archive_record.dart';
import '../../domain/repositories/archive_access_request_repository.dart';
import '../../domain/repositories/archive_repository.dart';
import '../../domain/repositories/saved_archive_records_repository.dart';

/// Archive repository: Supabase-backed when configured, local JSON otherwise.
final archiveRepositoryProvider = Provider<ArchiveRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return ArchiveRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return ArchiveRepositoryLocal(prefs);
});

/// Storage service for archive attachments (Supabase Storage + local fallback).
final archiveStorageServiceProvider = Provider<ArchiveStorageService>(
  (ref) => ArchiveStorageService(),
);

/// Every archive record (all statuses) — RLS restricts this to admins on
/// Supabase; the whole feature is unreachable in the UI for anyone else (see
/// isPlatformAdminProvider, watched by the screen that hosts this feature).
final archiveRecordsProvider = StreamProvider<List<ArchiveRecord>>((ref) {
  return ref.watch(archiveRepositoryProvider).watchAll();
});

final archiveRecordsPendingReviewProvider = Provider<List<ArchiveRecord>>((
  ref,
) {
  final List<ArchiveRecord> all =
      ref.watch(archiveRecordsProvider).value ?? const <ArchiveRecord>[];
  return all
      .where((r) => r.reviewStatus == ArchiveReviewStatus.pendingReview)
      .toList();
});

/// The record currently loaded into the Add record form for editing — set
/// when an admin taps a card on Stored collections, so drafts (and rejected
/// records) can be reopened and continued instead of only ever creating a
/// new record. Null means the form is blank / creating a new record.
final archiveRecordBeingEditedProvider = StateProvider<ArchiveRecord?>(
  (ref) => null,
);

/// Free-text search query for the Stored collections tab.
final archiveSearchProvider = StateProvider<String>((ref) => '');

/// Active type filter on Stored collections (null = "All").
final archiveTypeFilterProvider = StateProvider<RecordType?>((ref) => null);

final filteredArchiveRecordsProvider = Provider<List<ArchiveRecord>>((ref) {
  final List<ArchiveRecord> all =
      ref.watch(archiveRecordsProvider).value ?? const <ArchiveRecord>[];
  final String query = ref.watch(archiveSearchProvider).trim().toLowerCase();
  final RecordType? type = ref.watch(archiveTypeFilterProvider);

  return all.where((r) {
    if (type != null && r.type != type) return false;
    if (query.isEmpty) return true;
    final String haystack = <String>[
      r.title,
      r.collection,
      r.country,
      r.stateRegion,
      r.locality,
      r.repositorySource,
      r.contributor,
      r.recordRef ?? '',
      r.description ?? '',
      r.searchText ?? '',
      ...r.keywords,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }).toList();
});

// ── Public catalogue browsing ────────────────────────────────────────────

/// Published records only — for a non-admin, RLS (see
/// 20260921000000_archive_records_access_tiers.sql) already means
/// [archiveRepositoryProvider]'s `watchAll()` only ever returns published
/// rows, so filtering the same stream client-side is correct for both an
/// admin (who sees every status) and a regular signed-in user.
final publishedArchiveRecordsProvider = Provider<List<ArchiveRecord>>((ref) {
  final List<ArchiveRecord> all =
      ref.watch(archiveRecordsProvider).value ?? const <ArchiveRecord>[];
  return all.where((r) => r.reviewStatus == ArchiveReviewStatus.published).toList();
});

/// Free-text search query for the public Catalogue browser — kept separate
/// from [archiveSearchProvider] (the admin Stored-collections one) so the
/// two screens' in-progress searches never interfere with each other.
final catalogueSearchProvider = StateProvider<String>((ref) => '');

/// Active type filter on the Catalogue browser (null = "All").
final catalogueTypeFilterProvider = StateProvider<RecordType?>((ref) => null);

/// Active location (country or state/region) filter (null = "All").
final catalogueLocationFilterProvider = StateProvider<String?>((ref) => null);

/// Every distinct non-empty country/state-region value across published
/// records, for the location filter dropdown.
final catalogueLocationsProvider = Provider<List<String>>((ref) {
  final List<ArchiveRecord> all = ref.watch(publishedArchiveRecordsProvider);
  final Set<String> locations = <String>{};
  for (final ArchiveRecord r in all) {
    if (r.stateRegion.trim().isNotEmpty) locations.add(r.stateRegion.trim());
    if (r.country.trim().isNotEmpty) locations.add(r.country.trim());
  }
  final List<String> sorted = locations.toList()..sort();
  return sorted;
});

bool _matchesCatalogueFilters(
  ArchiveRecord r,
  String query,
  RecordType? type,
  String? location,
) {
  if (type != null && r.type != type) return false;
  if (location != null && r.country != location && r.stateRegion != location) {
    return false;
  }
  if (query.isEmpty) return true;
  final String haystack = <String>[
    r.title,
    r.collection,
    r.country,
    r.stateRegion,
    r.locality,
    r.repositorySource,
    r.recordRef ?? '',
    r.description ?? '',
    r.searchText ?? '',
    ...r.keywords,
  ].join(' ').toLowerCase();
  return haystack.contains(query);
}

final filteredCatalogueRecordsProvider = Provider<List<ArchiveRecord>>((ref) {
  final List<ArchiveRecord> all = ref.watch(publishedArchiveRecordsProvider);
  final String query = ref.watch(catalogueSearchProvider).trim().toLowerCase();
  final RecordType? type = ref.watch(catalogueTypeFilterProvider);
  final String? location = ref.watch(catalogueLocationFilterProvider);
  return all.where((r) => _matchesCatalogueFilters(r, query, type, location)).toList();
});

const Set<String> _avExtensions = <String>{'mp4', 'm4v', 'mov', 'mp3', 'm4a', 'wav'};

bool _hasAvFile(ArchiveRecord r) => r.files.any((f) {
  final String name = f.fileName.toLowerCase();
  final int dot = name.lastIndexOf('.');
  final String ext = dot >= 0 ? name.substring(dot + 1) : '';
  return _avExtensions.contains(ext);
});

/// Published records with at least one audio/video attachment — the Digital
/// films tab.
final catalogueFilmsProvider = Provider<List<ArchiveRecord>>((ref) {
  return ref.watch(publishedArchiveRecordsProvider).where(_hasAvFile).toList();
});

/// Same as [catalogueFilmsProvider] but respecting the active search/type/
/// location filters, so Digital films stays consistent with the other tabs.
final filteredCatalogueFilmsProvider = Provider<List<ArchiveRecord>>((ref) {
  final String query = ref.watch(catalogueSearchProvider).trim().toLowerCase();
  final RecordType? type = ref.watch(catalogueTypeFilterProvider);
  final String? location = ref.watch(catalogueLocationFilterProvider);
  return ref
      .watch(catalogueFilmsProvider)
      .where((r) => _matchesCatalogueFilters(r, query, type, location))
      .toList();
});

// ── Access requests (Permission tier) ────────────────────────────────────

final archiveAccessRequestRepositoryProvider =
    Provider<ArchiveAccessRequestRepository>((ref) {
      if (SupabaseConfig.isReady) {
        return ArchiveAccessRequestRepositorySupabase(SupabaseConfig.client);
      }
      final prefs = ref.watch(sharedPreferencesProvider);
      return ArchiveAccessRequestRepositoryLocal(prefs);
    });

/// The signed-in user's own access requests, across every record.
final myArchiveAccessRequestsProvider =
    StreamProvider<List<ArchiveAccessRequest>>((ref) {
      return ref.watch(archiveAccessRequestRepositoryProvider).watchMine();
    });

/// This user's request for [recordId], or null if they've never asked.
final archiveAccessRequestForRecordProvider = Provider.family<
  ArchiveAccessRequest?,
  String
>((ref, recordId) {
  final List<ArchiveAccessRequest> mine =
      ref.watch(myArchiveAccessRequestsProvider).value ??
      const <ArchiveAccessRequest>[];
  for (final r in mine) {
    if (r.recordId == recordId) return r;
  }
  return null;
});

/// All pending access requests — admin review tab only (RLS blocks this for
/// anyone else anyway).
final pendingArchiveAccessRequestsProvider =
    StreamProvider<List<ArchiveAccessRequest>>((ref) {
      return ref.watch(archiveAccessRequestRepositoryProvider).watchPending();
    });

// ── Saved ("bookmarked") records ─────────────────────────────────────────

final savedArchiveRecordsRepositoryProvider =
    Provider<SavedArchiveRecordsRepository>((ref) {
      if (SupabaseConfig.isReady) {
        return SavedArchiveRecordsRepositorySupabase(SupabaseConfig.client);
      }
      final prefs = ref.watch(sharedPreferencesProvider);
      return SavedArchiveRecordsRepositoryLocal(prefs);
    });

final savedArchiveRecordIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(savedArchiveRecordsRepositoryProvider).watchSavedIds();
});

final isArchiveRecordSavedProvider = Provider.family<bool, String>((
  ref,
  recordId,
) {
  final Set<String> saved =
      ref.watch(savedArchiveRecordIdsProvider).value ?? const <String>{};
  return saved.contains(recordId);
});

/// The signed-in user's bookmarked records, resolved against the published
/// catalogue — the "Saved" tab on the Catalogue browser. Resolving against
/// [publishedArchiveRecordsProvider] (rather than trusting the id set alone)
/// means a record that's since been unpublished quietly drops off here
/// instead of showing a broken entry.
final savedArchiveRecordsListProvider = Provider<List<ArchiveRecord>>((ref) {
  final Set<String> saved =
      ref.watch(savedArchiveRecordIdsProvider).value ?? const <String>{};
  if (saved.isEmpty) return const <ArchiveRecord>[];
  return ref
      .watch(publishedArchiveRecordsProvider)
      .where((r) => saved.contains(r.id))
      .toList();
});

/// Same as [savedArchiveRecordsListProvider] but respecting the active
/// search/type/location filters, consistent with the other Catalogue tabs.
final filteredSavedArchiveRecordsProvider = Provider<List<ArchiveRecord>>((ref) {
  final String query = ref.watch(catalogueSearchProvider).trim().toLowerCase();
  final RecordType? type = ref.watch(catalogueTypeFilterProvider);
  final String? location = ref.watch(catalogueLocationFilterProvider);
  return ref
      .watch(savedArchiveRecordsListProvider)
      .where((r) => _matchesCatalogueFilters(r, query, type, location))
      .toList();
});

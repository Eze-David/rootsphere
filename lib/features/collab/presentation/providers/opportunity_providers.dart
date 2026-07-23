import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/opportunity_repository_local.dart';
import '../../data/repositories/opportunity_repository_supabase.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/finder_submission.dart';
import '../../domain/entities/indexer_submission.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../../domain/repositories/opportunity_repository.dart';

final opportunityRepositoryProvider = Provider<OpportunityRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return OpportunityRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return OpportunityRepositoryLocal(prefs);
});

/// All opportunities on the collaboration board — an alias for
/// [opportunityControllerProvider]'s own state (kept as a separate name
/// since every screen already reads it as "the list", not "the mutator").
///
/// This used to be its own independent `StreamProvider` tied directly to
/// realtime, with the controller separately calling `ref.invalidate` on it
/// after every mutation to force a refetch. That relied on a brand new
/// realtime subscription reliably delivering a fresh snapshot fast enough to
/// feel instant, which wasn't reliably true — actions like claiming or
/// submitting for review would show as unchanged until the app restarted.
/// Routing through the controller instead means every mutation writes its
/// result straight into the one state both realtime and the UI share, so
/// there's nothing to "catch up" on.
final opportunitiesProvider =
    Provider<AsyncValue<List<CollaborationOpportunity>>>(
      (ref) => ref.watch(opportunityControllerProvider),
    );

/// Current filter tab for the opportunities board.
final opportunityFilterProvider = StateProvider<OpportunityStatus?>(
  (ref) => null,
);

/// Opportunities filtered by the selected status tab (null = all).
///
/// Excludes `forCompany` requests — those are only ever meant to be seen by
/// the company (via [companyOpportunitiesProvider]) or the requester who
/// sent it (via "My opportunities"), never mixed into the public community
/// board, even for an admin browsing it themselves.
final filteredOpportunitiesProvider = Provider<List<CollaborationOpportunity>>((
  ref,
) {
  final async = ref.watch(opportunitiesProvider);
  final filter = ref.watch(opportunityFilterProvider);
  final opportunities = (async.value ?? const <CollaborationOpportunity>[])
      .where((o) => !o.forCompany)
      .toList();
  if (filter == null) return opportunities;
  return opportunities.where((o) => o.status == filter).toList();
});

/// Counts of opportunities by status for the tab bar badges (public board
/// only — see [filteredOpportunitiesProvider]).
final opportunityCountsProvider = Provider<Map<OpportunityStatus, int>>((ref) {
  final async = ref.watch(opportunitiesProvider);
  final opportunities = (async.value ?? const <CollaborationOpportunity>[])
      .where((o) => !o.forCompany)
      .toList();
  return <OpportunityStatus, int>{
    OpportunityStatus.open: opportunities
        .where((o) => o.status == OpportunityStatus.open)
        .length,
    OpportunityStatus.claimed: opportunities
        .where((o) => o.status == OpportunityStatus.claimed)
        .length,
    OpportunityStatus.submitted: opportunities
        .where((o) => o.status == OpportunityStatus.submitted)
        .length,
    OpportunityStatus.companyApproved: opportunities
        .where((o) => o.status == OpportunityStatus.companyApproved)
        .length,
    OpportunityStatus.verified: opportunities
        .where((o) => o.status == OpportunityStatus.verified)
        .length,
  };
});

/// Every opportunity currently awaiting company review (any requester, any
/// tree) — RLS on `opportunities` already shows non-company rows to
/// everyone, so this list is meaningful for admins specifically; the review
/// screen is the only place it's used.
final pendingSubmissionsProvider = Provider<List<CollaborationOpportunity>>((
  ref,
) {
  final async = ref.watch(opportunitiesProvider);
  return (async.value ?? const <CollaborationOpportunity>[])
      .where((o) => o.isSubmitted)
      .toList();
});

/// Company-routed requests only — RLS already limits the underlying stream
/// to the requester and platform admins, so whichever of those the current
/// user is, this is exactly the set they're allowed to act on.
final companyOpportunitiesProvider = Provider<List<CollaborationOpportunity>>((
  ref,
) {
  final async = ref.watch(opportunitiesProvider);
  return (async.value ?? const <CollaborationOpportunity>[])
      .where((o) => o.forCompany)
      .toList();
});

/// Controller for mutating opportunities (claim, verify, create, etc.) —
/// also the single source of truth for the list itself (see
/// [opportunitiesProvider]).
///
/// State comes from two places that both write into the same `state`:
/// realtime pushes (other users' changes, kept live via the subscription
/// set up in [build]) and this controller's own mutations, which patch
/// `state` directly and synchronously with the row the server just returned
/// — no waiting on a fresh fetch or a new realtime subscription to "catch
/// up" before the UI reflects what the user just did.
class OpportunityController
    extends AsyncNotifier<List<CollaborationOpportunity>> {
  OpportunityRepository get _repo => ref.read(opportunityRepositoryProvider);
  StreamSubscription<List<CollaborationOpportunity>>? _subscription;

  @override
  Future<List<CollaborationOpportunity>> build() async {
    ref.onDispose(() => _subscription?.cancel());
    _subscription = _repo.watchOpportunities().listen(
      (list) {
        state = AsyncValue<List<CollaborationOpportunity>>.data(list);
      },
      onError: (Object e, StackTrace st) {
        state = AsyncValue<List<CollaborationOpportunity>>.error(e, st);
      },
    );
    return _repo.getOpportunities();
  }

  /// Writes [updated] straight into the current list — inserted at the top
  /// if it's new (a fresh `createOpportunity`), otherwise replacing the
  /// existing row with the same id.
  void _apply(CollaborationOpportunity updated) {
    final List<CollaborationOpportunity> current =
        state.value ?? const <CollaborationOpportunity>[];
    final int index = current.indexWhere((o) => o.id == updated.id);
    final List<CollaborationOpportunity> next = <CollaborationOpportunity>[
      ...current,
    ];
    if (index == -1) {
      next.insert(0, updated);
    } else {
      next[index] = updated;
    }
    state = AsyncValue<List<CollaborationOpportunity>>.data(next);
  }

  Future<CollaborationOpportunity> createOpportunity({
    required String treeId,
    required String title,
    required String description,
    String? location,
    double? latitude,
    double? longitude,
    CollaborationRole requiredRole = CollaborationRole.finder,
    bool forCompany = false,
  }) async {
    final opportunity = await _repo.createOpportunity(
      treeId: treeId,
      title: title,
      description: description,
      location: location,
      latitude: latitude,
      longitude: longitude,
      requiredRole: requiredRole,
      forCompany: forCompany,
    );
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> claim(String id) async {
    final opportunity = await _repo.claimOpportunity(id);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> submitResult(
    String id, {
    String? notes,
    String? url,
  }) async {
    final opportunity = await _repo.submitResult(id, notes: notes, url: url);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> saveFinderSubmission(
    String id,
    FinderSubmission submission,
  ) async {
    final opportunity = await _repo.saveFinderSubmission(id, submission);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> saveIndexerSubmission(
    String id,
    IndexerSubmission submission,
  ) async {
    final opportunity = await _repo.saveIndexerSubmission(id, submission);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> submitForReview(String id) async {
    final opportunity = await _repo.submitForReview(id);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> companyApprove(String id) async {
    final opportunity = await _repo.companyApprove(id);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> companyReject(
    String id,
    String feedback,
  ) async {
    final opportunity = await _repo.companyReject(id, feedback);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> verify(String id) async {
    final opportunity = await _repo.verifyOpportunity(id);
    _apply(opportunity);
    return opportunity;
  }

  Future<CollaborationOpportunity> unclaim(String id) async {
    final opportunity = await _repo.unclaimOpportunity(id);
    _apply(opportunity);
    return opportunity;
  }

  Future<void> saveSubject(String id, OpportunitySubject subject) async {
    await _repo.saveSubject(id, subject);
    ref.invalidate(opportunitySubjectProvider(id));
  }
}

final opportunityControllerProvider =
    AsyncNotifierProvider<
      OpportunityController,
      List<CollaborationOpportunity>
    >(OpportunityController.new);

/// Subject-person details for an opportunity — null if the requester didn't
/// add any. RLS restricts the underlying row to the requester, the claimer,
/// and platform admins, so this only ever resolves to data for whoever is
/// actually allowed to see it (see 20260722070000_opportunity_subjects.sql).
final opportunitySubjectProvider = FutureProvider.autoDispose
    .family<OpportunitySubject?, String>((ref, opportunityId) {
      final repo = ref.watch(opportunityRepositoryProvider);
      return repo.getSubject(opportunityId);
    });

/// Aggregated contribution stats derived from verified opportunities.
final contributionsProvider = Provider<List<UserContribution>>((ref) {
  final async = ref.watch(opportunitiesProvider);
  final opportunities = async.value ?? const <CollaborationOpportunity>[];
  final Map<String, UserContribution> byUser = <String, UserContribution>{};

  for (final o in opportunities) {
    if (o.claimerId == null) continue;
    final existing = byUser[o.claimerId];
    byUser[o.claimerId!] = UserContribution(
      userId: o.claimerId!,
      userName: o.claimerName ?? 'Unknown',
      claimedCount:
          (existing?.claimedCount ?? 0) +
          (o.isClaimed ? 1 : 0) +
          (o.isVerified ? 1 : 0),
      verifiedCount: (existing?.verifiedCount ?? 0) + (o.isVerified ? 1 : 0),
    );
  }

  return byUser.values.toList()
    ..sort((a, b) => b.reputation.compareTo(a.reputation));
});

/// Current user's contribution summary.
final myContributionProvider = Provider<UserContribution?>((ref) {
  final contributions = ref.watch(contributionsProvider);
  // Must go through the watched auth stream, not a direct
  // `Supabase...currentUser` read — otherwise this caches the first signed-in
  // user's uid and never re-evaluates after a sign-out/sign-in as someone
  // else, showing the previous account's contributions.
  final uid = ref.watch(authStateProvider).value?.id;
  if (uid == null) return null;
  return contributions.cast<UserContribution?>().firstWhere(
    (c) => c?.userId == uid,
    orElse: () => null,
  );
});

/// Opportunities the signed-in user has claimed (work they've taken on),
/// newest first — powers the "Claimed by me" tab on the My Opportunities
/// screen.
final myClaimedOpportunitiesProvider = Provider<List<CollaborationOpportunity>>(
  (ref) {
    final async = ref.watch(opportunitiesProvider);
    final uid = ref.watch(authStateProvider).value?.id;
    final opportunities = async.value ?? const <CollaborationOpportunity>[];
    if (uid == null) return const <CollaborationOpportunity>[];
    final List<CollaborationOpportunity> mine = opportunities
        .where((o) => o.claimerId == uid)
        .toList();
    mine.sort(
      (a, b) => (b.claimedAt ?? b.createdAt ?? DateTime(0)).compareTo(
        a.claimedAt ?? a.createdAt ?? DateTime(0),
      ),
    );
    return mine;
  },
);

/// Opportunities the signed-in user has posted (asked the community for
/// help with), newest first — powers the "Requested by me" tab.
final myRequestedOpportunitiesProvider =
    Provider<List<CollaborationOpportunity>>((ref) {
      final async = ref.watch(opportunitiesProvider);
      final uid = ref.watch(authStateProvider).value?.id;
      final opportunities = async.value ?? const <CollaborationOpportunity>[];
      if (uid == null) return const <CollaborationOpportunity>[];
      final List<CollaborationOpportunity> mine = opportunities
          .where((o) => o.requesterId == uid)
          .toList();
      mine.sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
      return mine;
    });

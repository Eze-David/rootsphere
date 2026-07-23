import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/finder_submission.dart';
import '../../domain/entities/indexer_submission.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../../domain/repositories/opportunity_repository.dart';

/// SharedPreferences-backed [OpportunityRepository] used when Supabase is not
/// configured. Streams are kept alive via an in-memory controller.
class OpportunityRepositoryLocal implements OpportunityRepository {
  OpportunityRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;
  final StreamController<List<CollaborationOpportunity>> _controller =
      StreamController<List<CollaborationOpportunity>>.broadcast();

  static const String _kKey = 'collab_opportunities_v1';
  static const String _kSubjectsKey = 'collab_opportunity_subjects_v1';

  String get _uid => Supabase.instance.client.auth.currentUser?.id ?? '';

  String get _userName {
    final user = Supabase.instance.client.auth.currentUser;
    final meta = user?.userMetadata;
    final name = (meta?['full_name'] ?? meta?['name']) as String?;
    return name?.trim().isNotEmpty == true
        ? name!.trim()
        : user?.email ?? 'You';
  }

  List<CollaborationOpportunity> _read() {
    final String? raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return _seed();
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => CollaborationOpportunity.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return _seed();
    }
  }

  List<CollaborationOpportunity> _seed() {
    final List<CollaborationOpportunity> seeded = <CollaborationOpportunity>[
      CollaborationOpportunity(
        id: 'opp_demo_1',
        treeId: 'demo',
        title: '1901 census · County Cork, surname Brennan',
        description:
            'Searching for census entry confirming address and household of Patrick Brennan, approx. age 34.',
        location: 'Cork, Ireland',
        latitude: 51.8985,
        longitude: -8.4756,
        requiredRole: CollaborationRole.finder,
        requesterId: 'demo_user',
        requesterName: 'Demo User',
        status: OpportunityStatus.open,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      CollaborationOpportunity(
        id: 'opp_demo_2',
        treeId: 'demo',
        title: 'Lagos marriage register 1952',
        description:
            'Bello-Okafor union certificate from Ikoyi registry office.',
        location: 'Lagos, Nigeria',
        latitude: 6.5244,
        longitude: 3.3792,
        requiredRole: CollaborationRole.finder,
        requesterId: 'demo_user',
        requesterName: 'Demo User',
        claimerId: 'claimer_demo',
        claimerName: 'Chidi A.',
        status: OpportunityStatus.claimed,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        claimedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      CollaborationOpportunity(
        id: 'opp_demo_3',
        treeId: 'demo',
        title: 'Ship manifest · SS Apapa 1937',
        description:
            'Passenger list Lagos → Liverpool, looking for Okonkwo family entry.',
        location: 'Liverpool, UK',
        latitude: 53.4084,
        longitude: -2.9916,
        requiredRole: CollaborationRole.indexer,
        requesterId: 'demo_user',
        requesterName: 'Demo User',
        status: OpportunityStatus.open,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
    _write(seeded);
    return seeded;
  }

  Future<void> _write(List<CollaborationOpportunity> opportunities) async {
    final String encoded = jsonEncode(
      opportunities.map((o) => o.toJson()).toList(),
    );
    await _prefs.setString(_kKey, encoded);
    if (!_controller.isClosed) _controller.add(opportunities);
  }

  @override
  Future<List<CollaborationOpportunity>> getOpportunities() async => _read();

  @override
  Stream<List<CollaborationOpportunity>> watchOpportunities() {
    scheduleMicrotask(() => _controller.add(_read()));
    return _controller.stream;
  }

  @override
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
    final opportunities = _read();
    final opportunity = CollaborationOpportunity(
      id: 'opp_${DateTime.now().millisecondsSinceEpoch}',
      treeId: treeId,
      title: title,
      description: description,
      location: location,
      latitude: latitude,
      longitude: longitude,
      requiredRole: requiredRole,
      requesterId: _uid,
      requesterName: _userName,
      status: OpportunityStatus.open,
      forCompany: forCompany,
      createdAt: DateTime.now(),
    );
    await _write(<CollaborationOpportunity>[...opportunities, opportunity]);
    return opportunity;
  }

  @override
  Future<CollaborationOpportunity> claimOpportunity(String id) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final current = opportunities[index];
    if (!current.isOpen) throw Exception('This opportunity is no longer open.');
    final updated = current.copyWith(
      status: OpportunityStatus.claimed,
      claimerId: _uid,
      claimerName: _userName,
      claimedAt: DateTime.now(),
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> submitResult(
    String id, {
    String? notes,
    String? url,
  }) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      resultNotes: notes,
      resultUrl: url,
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> saveFinderSubmission(
    String id,
    FinderSubmission submission,
  ) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(finderSubmission: submission);
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> saveIndexerSubmission(
    String id,
    IndexerSubmission submission,
  ) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      indexerSubmission: submission,
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> submitForReview(String id) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      status: OpportunityStatus.submitted,
      submittedAt: DateTime.now(),
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> companyApprove(String id) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      status: OpportunityStatus.companyApproved,
      companyApprovedAt: DateTime.now(),
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> companyReject(
    String id,
    String feedback,
  ) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      status: OpportunityStatus.claimed,
      companyFeedback: feedback,
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> verifyOpportunity(String id) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      status: OpportunityStatus.verified,
      verifiedAt: DateTime.now(),
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<CollaborationOpportunity> unclaimOpportunity(String id) async {
    final opportunities = _read();
    final index = opportunities.indexWhere((o) => o.id == id);
    if (index == -1) throw Exception('Opportunity not found.');
    final updated = opportunities[index].copyWith(
      status: OpportunityStatus.open,
      claimerId: null,
      claimerName: null,
      claimedAt: null,
      resultNotes: null,
      resultUrl: null,
      finderSubmission: null,
      indexerSubmission: null,
      companyFeedback: null,
      submittedAt: null,
      companyApprovedAt: null,
    );
    opportunities[index] = updated;
    await _write(opportunities);
    return updated;
  }

  @override
  Future<OpportunitySubject?> getSubject(String opportunityId) async {
    final String? raw = _prefs.getString(_kSubjectsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final Map<String, dynamic>? json =
          all[opportunityId] as Map<String, dynamic>?;
      return json == null ? null : OpportunitySubject.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSubject(
    String opportunityId,
    OpportunitySubject subject,
  ) async {
    final String? raw = _prefs.getString(_kSubjectsKey);
    final Map<String, dynamic> all = raw == null || raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    all[opportunityId] = subject.toJson();
    await _prefs.setString(_kSubjectsKey, jsonEncode(all));
  }
}

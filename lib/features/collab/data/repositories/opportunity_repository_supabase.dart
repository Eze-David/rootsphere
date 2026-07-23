import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/finder_submission.dart';
import '../../domain/entities/indexer_submission.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../../domain/repositories/opportunity_repository.dart';

/// Supabase-backed [OpportunityRepository].
///
/// Opportunities are stored in the `opportunities` table and read via realtime
/// stream so the board updates live. The status lifecycle is enforced by the
/// application layer.
class OpportunityRepositorySupabase implements OpportunityRepository {
  OpportunityRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _opportunities => _client.from('opportunities');
  SupabaseQueryBuilder get _trees => _client.from('trees');
  SupabaseQueryBuilder get _subjects => _client.from('opportunity_subjects');

  String get _uid => _client.auth.currentUser?.id ?? '';

  String get _userName {
    final user = _client.auth.currentUser;
    final meta = user?.userMetadata;
    final name = (meta?['full_name'] ?? meta?['name']) as String?;
    return name?.trim().isNotEmpty == true
        ? name!.trim()
        : user?.email ?? 'You';
  }

  @override
  Future<List<CollaborationOpportunity>> getOpportunities() async {
    try {
      final List<dynamic> rows = await _opportunities.select().order(
        'created_at',
      );
      return rows
          .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Stream<List<CollaborationOpportunity>> watchOpportunities() {
    return _opportunities
        .stream(primaryKey: <String>['id'])
        .order('created_at')
        .map(
          (rows) => rows
              .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
              .toList(),
        );
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
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    final String id = 'opp_${DateTime.now().millisecondsSinceEpoch}';
    await _ensureTree(treeId);
    try {
      final Map<String, dynamic> row = await _opportunities
          .insert(<String, dynamic>{
            'id': id,
            'tree_id': treeId,
            'title': title,
            'description': description,
            'location': location,
            'latitude': latitude,
            'longitude': longitude,
            'required_role': requiredRole.name,
            'requester_id': _uid,
            'requester_name': _userName,
            'status': opportunityStatusToDb(OpportunityStatus.open),
            'for_company': forCompany,
          })
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  /// Creates the tree row if it doesn't exist yet (opportunities FK to it).
  /// Mirrors TreeRepositorySupabase._ensureTree — needed here too because an
  /// opportunity can be the very first thing a user creates in a tree that's
  /// otherwise never had a person added (which is what normally creates
  /// this row), and the FK constraint doesn't forgive a missing one.
  Future<void> _ensureTree(String treeId) async {
    try {
      await _trees.upsert(
        <String, dynamic>{
          'id': treeId,
          'owner_id': _uid,
          'name': treeId == 'okonkwo' ? 'Okonkwo' : 'My Family Tree',
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> claimOpportunity(String id) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{
            'status': opportunityStatusToDb(OpportunityStatus.claimed),
            'claimer_id': _uid,
            'claimer_name': _userName,
            'claimed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('status', opportunityStatusToDb(OpportunityStatus.open))
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> submitResult(
    String id, {
    String? notes,
    String? url,
  }) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{'result_notes': notes, 'result_url': url})
          .eq('id', id)
          .eq('claimer_id', _uid)
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> saveFinderSubmission(
    String id,
    FinderSubmission submission,
  ) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{'finder_submission': submission.toJson()})
          .eq('id', id)
          .eq('claimer_id', _uid)
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> saveIndexerSubmission(
    String id,
    IndexerSubmission submission,
  ) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{'indexer_submission': submission.toJson()})
          .eq('id', id)
          .eq('claimer_id', _uid)
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> submitForReview(String id) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{
            'status': opportunityStatusToDb(OpportunityStatus.submitted),
            'submitted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('claimer_id', _uid)
          .eq('status', opportunityStatusToDb(OpportunityStatus.claimed))
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> companyApprove(String id) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{
            'status': opportunityStatusToDb(OpportunityStatus.companyApproved),
            'company_approved_at': DateTime.now().toIso8601String(),
            'company_reviewed_by': _uid,
          })
          .eq('id', id)
          .eq('status', opportunityStatusToDb(OpportunityStatus.submitted))
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> companyReject(
    String id,
    String feedback,
  ) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{
            'status': opportunityStatusToDb(OpportunityStatus.claimed),
            'company_feedback': feedback,
            'company_reviewed_by': _uid,
          })
          .eq('id', id)
          .eq('status', opportunityStatusToDb(OpportunityStatus.submitted))
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> verifyOpportunity(String id) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{
            'status': opportunityStatusToDb(OpportunityStatus.verified),
            'verified_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq(
            'status',
            opportunityStatusToDb(OpportunityStatus.companyApproved),
          )
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<CollaborationOpportunity> unclaimOpportunity(String id) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      final Map<String, dynamic> row = await _opportunities
          .update(<String, dynamic>{
            'status': opportunityStatusToDb(OpportunityStatus.open),
            'claimer_id': null,
            'claimer_name': null,
            'claimed_at': null,
            'result_notes': null,
            'result_url': null,
            'finder_submission': null,
            'indexer_submission': null,
            'company_feedback': null,
            'submitted_at': null,
            'company_approved_at': null,
            'company_reviewed_by': null,
            'verified_at': null,
          })
          .eq('id', id)
          .eq('claimer_id', _uid)
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<OpportunitySubject?> getSubject(String opportunityId) async {
    try {
      final Map<String, dynamic>? row = await _subjects
          .select()
          .eq('opportunity_id', opportunityId)
          .maybeSingle();
      if (row == null) return null;
      return _subjectFromRow(row);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> saveSubject(
    String opportunityId,
    OpportunitySubject subject,
  ) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      await _subjects.upsert(<String, dynamic>{
        'opportunity_id': opportunityId,
        'first_name': subject.firstName,
        'middle_name': subject.middleName,
        'last_name': subject.lastName,
        'nick_name': subject.nickName,
        'country': subject.country,
        'additional_info': subject.additionalInfo,
        'photo_urls': subject.photoUrls,
        'document_urls': subject.documentUrls,
      }, onConflict: 'opportunity_id');
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  OpportunitySubject _subjectFromRow(Map<String, dynamic> row) {
    return OpportunitySubject(
      firstName: row['first_name'] as String? ?? '',
      middleName: row['middle_name'] as String? ?? '',
      lastName: row['last_name'] as String? ?? '',
      nickName: row['nick_name'] as String? ?? '',
      country: row['country'] as String? ?? '',
      additionalInfo: row['additional_info'] as String?,
      photoUrls: (row['photo_urls'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      documentUrls:
          (row['document_urls'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(),
    );
  }

  CollaborationOpportunity _fromRow(Map<String, dynamic> row) {
    return CollaborationOpportunity(
      id: row['id'] as String,
      treeId: row['tree_id'] as String? ?? '',
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      location: row['location'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      requiredRole: CollaborationRole.values.firstWhere(
        (r) => r.name == row['required_role'],
        orElse: () => CollaborationRole.finder,
      ),
      requesterId: row['requester_id'] as String? ?? '',
      requesterName: row['requester_name'] as String? ?? '',
      claimerId: row['claimer_id'] as String?,
      claimerName: row['claimer_name'] as String?,
      finderSubmission: row['finder_submission'] == null
          ? null
          : FinderSubmission.fromJson(
              Map<String, dynamic>.from(row['finder_submission'] as Map),
            ),
      indexerSubmission: row['indexer_submission'] == null
          ? null
          : IndexerSubmission.fromJson(
              Map<String, dynamic>.from(row['indexer_submission'] as Map),
            ),
      status: opportunityStatusFromDb(row['status'] as String?),
      resultNotes: row['result_notes'] as String?,
      resultUrl: row['result_url'] as String?,
      forCompany: row['for_company'] as bool? ?? false,
      companyFeedback: row['company_feedback'] as String?,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse(row['created_at'].toString()),
      claimedAt: row['claimed_at'] == null
          ? null
          : DateTime.tryParse(row['claimed_at'].toString()),
      submittedAt: row['submitted_at'] == null
          ? null
          : DateTime.tryParse(row['submitted_at'].toString()),
      companyApprovedAt: row['company_approved_at'] == null
          ? null
          : DateTime.tryParse(row['company_approved_at'].toString()),
      verifiedAt: row['verified_at'] == null
          ? null
          : DateTime.tryParse(row['verified_at'].toString()),
    );
  }
}

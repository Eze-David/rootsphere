import 'package:flutter/material.dart';

import 'finder_submission.dart';
import 'indexer_submission.dart';

/// Lifecycle of a collaboration opportunity on the record-gathering board.
/// A claimer's submission no longer goes straight to the requester — it
/// passes through the company first: claimed -> submitted ->
/// companyApproved -> verified (or back to claimed, rejected with feedback).
/// See supabase/migrations/20260722080000_opportunity_review_pipeline.sql.
enum OpportunityStatus { open, claimed, submitted, companyApproved, verified }

extension OpportunityStatusX on OpportunityStatus {
  String get label {
    switch (this) {
      case OpportunityStatus.open:
        return 'Open';
      case OpportunityStatus.claimed:
        return 'Claimed';
      case OpportunityStatus.submitted:
        return 'Submitted';
      case OpportunityStatus.companyApproved:
        return 'Approved';
      case OpportunityStatus.verified:
        return 'Verified';
    }
  }
}

/// The `status` column uses snake_case (matching this codebase's other
/// text-enum columns, e.g. notification `type`), which doesn't match Dart's
/// camelCase enum names — mapped explicitly rather than via `.name` so
/// `companyApproved` doesn't silently serialize as the wrong string.
String opportunityStatusToDb(OpportunityStatus status) {
  switch (status) {
    case OpportunityStatus.open:
      return 'open';
    case OpportunityStatus.claimed:
      return 'claimed';
    case OpportunityStatus.submitted:
      return 'submitted';
    case OpportunityStatus.companyApproved:
      return 'company_approved';
    case OpportunityStatus.verified:
      return 'verified';
  }
}

OpportunityStatus opportunityStatusFromDb(String? value) {
  switch (value) {
    case 'claimed':
      return OpportunityStatus.claimed;
    case 'submitted':
      return OpportunityStatus.submitted;
    case 'company_approved':
      return OpportunityStatus.companyApproved;
    case 'verified':
      return OpportunityStatus.verified;
    case 'open':
    default:
      return OpportunityStatus.open;
  }
}

/// The type of contributor needed for an opportunity.
enum CollaborationRole { finder, indexer }

extension CollaborationRoleX on CollaborationRole {
  String get label {
    switch (this) {
      case CollaborationRole.finder:
        return 'Finder';
      case CollaborationRole.indexer:
        return 'Indexer';
    }
  }

  String get description {
    switch (this) {
      case CollaborationRole.finder:
        return 'Researcher / Genealogist: locate records, evaluate evidence, analyze DNA matches, and compile findings.';
      case CollaborationRole.indexer:
        return 'Transcriber / Data Clerk: type text from scanned documents, verify accuracy, and add searchable metadata.';
    }
  }

  IconData get icon {
    switch (this) {
      case CollaborationRole.finder:
        return Icons.search;
      case CollaborationRole.indexer:
        return Icons.keyboard;
    }
  }
}

/// A request for the community to help find or verify a record.
class CollaborationOpportunity {
  const CollaborationOpportunity({
    required this.id,
    required this.treeId,
    required this.title,
    required this.description,
    required this.requesterId,
    required this.requesterName,
    this.location,
    this.latitude,
    this.longitude,
    this.requiredRole = CollaborationRole.finder,
    this.status = OpportunityStatus.open,
    this.claimerId,
    this.claimerName,
    this.finderSubmission,
    this.indexerSubmission,
    this.resultNotes,
    this.resultUrl,
    this.forCompany = false,
    this.companyFeedback,
    this.createdAt,
    this.claimedAt,
    this.submittedAt,
    this.companyApprovedAt,
    this.verifiedAt,
  });

  final String id;
  final String treeId;
  final String title;
  final String description;

  /// Optional location label, e.g. "Lagos, Nigeria".
  final String? location;

  /// Optional geo coordinates for the map view.
  final double? latitude;
  final double? longitude;

  /// The type of contributor needed (Finder = researcher, Indexer = transcriber).
  final CollaborationRole requiredRole;

  /// The user who created the opportunity.
  final String requesterId;
  final String requesterName;

  /// The user who claimed it (null while open).
  final String? claimerId;
  final String? claimerName;

  /// Role-specific work-in-progress submissions.
  final FinderSubmission? finderSubmission;
  final IndexerSubmission? indexerSubmission;

  final OpportunityStatus status;

  /// Notes / proof supplied by the claimer.
  final String? resultNotes;

  /// Link to an uploaded record, image, or external source.
  final String? resultUrl;

  /// Sent directly to the company instead of the public community board —
  /// hidden from other members (enforced server-side by RLS) and claimable
  /// only by a platform admin, skipping the usual role-qualification check.
  final bool forCompany;

  /// Set by the company when it rejects a submission back to the claimer
  /// (status returns to `claimed`) — explains what needs fixing.
  final String? companyFeedback;

  final DateTime? createdAt;
  final DateTime? claimedAt;
  final DateTime? submittedAt;
  final DateTime? companyApprovedAt;
  final DateTime? verifiedAt;

  bool get isOpen => status == OpportunityStatus.open;
  bool get isClaimed => status == OpportunityStatus.claimed;
  bool get isSubmitted => status == OpportunityStatus.submitted;
  bool get isCompanyApproved => status == OpportunityStatus.companyApproved;
  bool get isVerified => status == OpportunityStatus.verified;
  bool get hasGeo => latitude != null && longitude != null;

  /// True once the company has sent a submission back to the claimer
  /// (status returns to `claimed`, with feedback attached) and they haven't
  /// resubmitted yet — a distinct state from a fresh, never-submitted claim,
  /// even though both share the same underlying status.
  bool get changesRequested =>
      isClaimed && (companyFeedback ?? '').trim().isNotEmpty;

  // Every optional field below uses the sentinel pattern (not plain `??`) so
  // callers can explicitly clear a field by passing `null` — e.g. unclaiming
  // resets claimerId/finderSubmission/etc. back to null. A plain `??` would
  // silently ignore an explicit null and keep the old value instead.
  CollaborationOpportunity copyWith({
    OpportunityStatus? status,
    Object? claimerId = _sentinel,
    Object? claimerName = _sentinel,
    Object? finderSubmission = _sentinel,
    Object? indexerSubmission = _sentinel,
    Object? resultNotes = _sentinel,
    Object? resultUrl = _sentinel,
    Object? companyFeedback = _sentinel,
    Object? claimedAt = _sentinel,
    Object? submittedAt = _sentinel,
    Object? companyApprovedAt = _sentinel,
    Object? verifiedAt = _sentinel,
  }) {
    return CollaborationOpportunity(
      id: id,
      treeId: treeId,
      title: title,
      description: description,
      requesterId: requesterId,
      requesterName: requesterName,
      location: location,
      latitude: latitude,
      longitude: longitude,
      requiredRole: requiredRole,
      status: status ?? this.status,
      claimerId: claimerId == _sentinel ? this.claimerId : claimerId as String?,
      claimerName: claimerName == _sentinel
          ? this.claimerName
          : claimerName as String?,
      finderSubmission: finderSubmission == _sentinel
          ? this.finderSubmission
          : finderSubmission as FinderSubmission?,
      indexerSubmission: indexerSubmission == _sentinel
          ? this.indexerSubmission
          : indexerSubmission as IndexerSubmission?,
      resultNotes: resultNotes == _sentinel
          ? this.resultNotes
          : resultNotes as String?,
      resultUrl: resultUrl == _sentinel ? this.resultUrl : resultUrl as String?,
      forCompany: forCompany,
      companyFeedback: companyFeedback == _sentinel
          ? this.companyFeedback
          : companyFeedback as String?,
      createdAt: createdAt,
      claimedAt: claimedAt == _sentinel
          ? this.claimedAt
          : claimedAt as DateTime?,
      submittedAt: submittedAt == _sentinel
          ? this.submittedAt
          : submittedAt as DateTime?,
      companyApprovedAt: companyApprovedAt == _sentinel
          ? this.companyApprovedAt
          : companyApprovedAt as DateTime?,
      verifiedAt: verifiedAt == _sentinel
          ? this.verifiedAt
          : verifiedAt as DateTime?,
    );
  }

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'treeId': treeId,
    'title': title,
    'description': description,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'requiredRole': requiredRole.name,
    'requesterId': requesterId,
    'requesterName': requesterName,
    'claimerId': claimerId,
    'claimerName': claimerName,
    'finderSubmission': finderSubmission?.toJson(),
    'indexerSubmission': indexerSubmission?.toJson(),
    'status': status.name,
    'resultNotes': resultNotes,
    'resultUrl': resultUrl,
    'forCompany': forCompany,
    'companyFeedback': companyFeedback,
    'createdAt': createdAt?.toIso8601String(),
    'claimedAt': claimedAt?.toIso8601String(),
    'submittedAt': submittedAt?.toIso8601String(),
    'companyApprovedAt': companyApprovedAt?.toIso8601String(),
    'verifiedAt': verifiedAt?.toIso8601String(),
  };

  factory CollaborationOpportunity.fromJson(Map<String, dynamic> json) {
    return CollaborationOpportunity(
      id: json['id'] as String,
      treeId: json['treeId'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: json['location'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      requiredRole: CollaborationRole.values.firstWhere(
        (r) => r.name == json['requiredRole'],
        orElse: () => CollaborationRole.finder,
      ),
      requesterId: json['requesterId'] as String? ?? '',
      requesterName: json['requesterName'] as String? ?? '',
      claimerId: json['claimerId'] as String?,
      claimerName: json['claimerName'] as String?,
      finderSubmission: json['finderSubmission'] == null
          ? null
          : FinderSubmission.fromJson(
              json['finderSubmission'] as Map<String, dynamic>,
            ),
      indexerSubmission: json['indexerSubmission'] == null
          ? null
          : IndexerSubmission.fromJson(
              json['indexerSubmission'] as Map<String, dynamic>,
            ),
      status: OpportunityStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => OpportunityStatus.open,
      ),
      resultNotes: json['resultNotes'] as String?,
      resultUrl: json['resultUrl'] as String?,
      forCompany: json['forCompany'] as bool? ?? false,
      companyFeedback: json['companyFeedback'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      claimedAt: json['claimedAt'] == null
          ? null
          : DateTime.tryParse(json['claimedAt'].toString()),
      submittedAt: json['submittedAt'] == null
          ? null
          : DateTime.tryParse(json['submittedAt'].toString()),
      companyApprovedAt: json['companyApprovedAt'] == null
          ? null
          : DateTime.tryParse(json['companyApprovedAt'].toString()),
      verifiedAt: json['verifiedAt'] == null
          ? null
          : DateTime.tryParse(json['verifiedAt'].toString()),
    );
  }
}

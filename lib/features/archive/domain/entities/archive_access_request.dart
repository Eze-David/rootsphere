enum ArchiveAccessRequestStatus { pending, approved, rejected }

/// A user's request to view a `Permission`-tier [ArchiveRecord]'s
/// attachments. Rows are only ever created by the requester and reviewed
/// (approved/rejected) by an admin — see
/// supabase/migrations/20260921000100_archive_access_requests.sql.
/// Approving flips the record itself to `Online` for everyone (no per-user
/// file ACLs in this pass).
class ArchiveAccessRequest {
  const ArchiveAccessRequest({
    required this.id,
    required this.recordId,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.note,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String id;
  final String recordId;
  final String userId;
  final ArchiveAccessRequestStatus status;
  final DateTime createdAt;
  final String? note;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  factory ArchiveAccessRequest.fromJson(Map<String, dynamic> json) {
    return ArchiveAccessRequest(
      id: json['id'] as String,
      recordId: json['record_id'] as String,
      userId: json['user_id'] as String,
      status: ArchiveAccessRequestStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ArchiveAccessRequestStatus.pending,
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      note: json['note'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'].toString())
          : null,
      reviewedBy: json['reviewed_by'] as String?,
    );
  }
}

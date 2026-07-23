import 'opportunity.dart';

enum VerificationStatus { pending, approved, rejected }

/// A user's application to be qualified for a [CollaborationRole] — required
/// before they're allowed to claim an opportunity needing that role. Rows
/// are only ever created by the applicant themselves and reviewed
/// (approved/rejected) by the company — see
/// supabase/migrations/20260722020000_role_verifications.sql.
class RoleVerification {
  const RoleVerification({
    required this.id,
    required this.userId,
    required this.role,
    required this.status,
    required this.createdAt,
    this.note,
    this.reviewedAt,
    required this.applicantName,
    required this.applicantEmail,
    required this.applicantPhone,
    this.documentUrls = const <String>[],
    this.governmentIdUrl,
  });

  final String id;
  final String userId;
  final CollaborationRole role;
  final VerificationStatus status;
  final DateTime createdAt;
  final String? note;
  final DateTime? reviewedAt;

  /// Name is captured automatically from the account; email and phone are
  /// entered explicitly by the applicant (email defaults to the account's
  /// but is editable, in case they want a different contact address) so the
  /// company has a confirmed way to reach an approved Finder/Indexer.
  final String applicantName;
  final String applicantEmail;
  final String applicantPhone;

  /// Supporting certificates/credentials the applicant attached — optional,
  /// since not everyone has a formal certificate but may still be worth
  /// approving on experience alone.
  final List<String> documentUrls;

  /// One government-issued ID, required for identity verification.
  final String? governmentIdUrl;

  factory RoleVerification.fromJson(Map<String, dynamic> json) {
    return RoleVerification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      role: CollaborationRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => CollaborationRole.finder,
      ),
      status: VerificationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => VerificationStatus.pending,
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      note: json['note'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'].toString())
          : null,
      applicantName: json['applicant_name'] as String? ?? 'Unknown',
      applicantEmail: json['applicant_email'] as String? ?? '',
      applicantPhone: json['applicant_phone'] as String? ?? '',
      documentUrls:
          (json['document_urls'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(),
      governmentIdUrl: json['government_id_url'] as String?,
    );
  }
}

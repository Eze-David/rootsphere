/// What triggered a notification — drives the icon shown in the list and,
/// for some types, where tapping it navigates.
enum NotificationType {
  treeActivity,
  opportunityClaimed,
  opportunityVerified,
  donationReceived,
  treeMemberJoined,
  opportunityCompanyRequest,
  opportunitySubmitted,
  opportunityCompanyApproved,
  opportunityCompanyRejected,
  supportMessage,
  supportReply,
  unknown,
}

// The `type` column stores snake_case values (see
// supabase/migrations/20260722010000_notifications.sql) — these don't match
// the Dart enum names' casing, so they're mapped explicitly rather than via
// `NotificationType.values.byName`.
NotificationType _typeFromString(String value) {
  switch (value) {
    case 'tree_activity':
      return NotificationType.treeActivity;
    case 'opportunity_claimed':
      return NotificationType.opportunityClaimed;
    case 'opportunity_verified':
      return NotificationType.opportunityVerified;
    case 'donation_received':
      return NotificationType.donationReceived;
    case 'tree_member_joined':
      return NotificationType.treeMemberJoined;
    case 'opportunity_company_request':
      return NotificationType.opportunityCompanyRequest;
    case 'opportunity_submitted':
      return NotificationType.opportunitySubmitted;
    case 'opportunity_company_approved':
      return NotificationType.opportunityCompanyApproved;
    case 'opportunity_company_rejected':
      return NotificationType.opportunityCompanyRejected;
    case 'support_message':
      return NotificationType.supportMessage;
    case 'support_reply':
      return NotificationType.supportReply;
    default:
      return NotificationType.unknown;
  }
}

/// A single in-app notification (the bell icon on Home). Generated
/// server-side by database triggers — see
/// supabase/migrations/20260722010000_notifications.sql — never inserted
/// directly by the client.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.treeId,
    this.personId,
    this.opportunityId,
  });

  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  final String? treeId;
  final String? personId;
  final String? opportunityId;

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      read: read ?? this.read,
      createdAt: createdAt,
      treeId: treeId,
      personId: personId,
      opportunityId: opportunityId,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: _typeFromString(json['type'] as String? ?? ''),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      treeId: json['tree_id'] as String?,
      personId: json['person_id'] as String?,
      opportunityId: json['opportunity_id'] as String?,
    );
  }
}

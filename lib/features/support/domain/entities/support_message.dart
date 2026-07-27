enum SupportMessageStatus { open, resolved }

/// A user-submitted "Contact us" message (Profile ▸ Support). Rows are
/// inserted by the sender and read/resolved by platform admins — see
/// supabase/migrations/20260724020000_support_messages.sql.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.userId,
    required this.email,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String email;
  final String message;
  final SupportMessageStatus status;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      email: json['email'] as String? ?? '',
      message: json['message'] as String? ?? '',
      status: SupportMessageStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SupportMessageStatus.open,
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

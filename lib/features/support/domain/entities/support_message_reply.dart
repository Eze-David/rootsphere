/// A single reply within a [SupportMessage]'s thread — from either the
/// admin or the original sender. See
/// supabase/migrations/20260724030000_support_message_replies.sql.
class SupportMessageReply {
  const SupportMessageReply({
    required this.id,
    required this.supportMessageId,
    required this.authorId,
    required this.isAdminReply,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String supportMessageId;
  final String authorId;
  final bool isAdminReply;
  final String body;
  final DateTime createdAt;

  factory SupportMessageReply.fromJson(Map<String, dynamic> json) {
    return SupportMessageReply(
      id: json['id'] as String,
      supportMessageId: json['support_message_id'] as String,
      authorId: json['author_id'] as String,
      isAdminReply: json['is_admin_reply'] as bool? ?? false,
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

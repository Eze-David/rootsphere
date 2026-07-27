import '../entities/support_message.dart';
import '../entities/support_message_reply.dart';

/// Persistence contract for "Contact us" messages. See
/// supabase/migrations/20260724020000_support_messages.sql and
/// 20260724030000_support_message_replies.sql.
abstract class SupportMessageRepository {
  /// Submits a new message from the signed-in user.
  Future<void> send({required String email, required String message});

  /// Messages visible to the signed-in caller: everyone's for an admin
  /// (the inbox), or just their own (RLS-enforced either way).
  Stream<List<SupportMessage>> watchAll();

  Future<void> markResolved(String id);

  /// A message's reply thread, oldest first.
  Stream<List<SupportMessageReply>> watchReplies(String messageId);

  /// Replies as the signed-in user — either the admin or the original
  /// sender (RLS decides which; author/admin-flag are set server-side).
  Future<void> reply(String messageId, String body);
}

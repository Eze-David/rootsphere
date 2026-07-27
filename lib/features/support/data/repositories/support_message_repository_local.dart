import '../../domain/entities/support_message.dart';
import '../../domain/entities/support_message_reply.dart';
import '../../domain/repositories/support_message_repository.dart';

/// Offline/no-Supabase fallback. Support is inherently a server-mediated,
/// multi-user process, so there's nothing meaningful to simulate locally.
class SupportMessageRepositoryLocal implements SupportMessageRepository {
  @override
  Future<void> send({required String email, required String message}) async {}

  @override
  Stream<List<SupportMessage>> watchAll() =>
      Stream<List<SupportMessage>>.value(const <SupportMessage>[]);

  @override
  Future<void> markResolved(String id) async {}

  @override
  Stream<List<SupportMessageReply>> watchReplies(String messageId) =>
      Stream<List<SupportMessageReply>>.value(const <SupportMessageReply>[]);

  @override
  Future<void> reply(String messageId, String body) async {}
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/support_message.dart';
import '../../domain/entities/support_message_reply.dart';
import '../../domain/repositories/support_message_repository.dart';

class SupportMessageRepositorySupabase implements SupportMessageRepository {
  SupportMessageRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('support_messages');
  SupabaseQueryBuilder get _repliesTable =>
      _client.from('support_message_replies');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Future<void> send({required String email, required String message}) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      await _table.insert(<String, dynamic>{
        'user_id': _uid,
        'email': email,
        'message': message,
      });
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Stream<List<SupportMessage>> watchAll() {
    return _table
        .stream(primaryKey: <String>['id'])
        .order('created_at')
        .map(
          (rows) => rows.map(SupportMessage.fromJson).toList().reversed
              .toList(),
        );
  }

  @override
  Future<void> markResolved(String id) async {
    try {
      await _table
          .update(<String, dynamic>{'status': 'resolved'})
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Stream<List<SupportMessageReply>> watchReplies(String messageId) {
    return _repliesTable
        .stream(primaryKey: <String>['id'])
        .eq('support_message_id', messageId)
        .order('created_at')
        .map((rows) => rows.map(SupportMessageReply.fromJson).toList());
  }

  @override
  Future<void> reply(String messageId, String body) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      await _repliesTable.insert(<String, dynamic>{
        'support_message_id': messageId,
        'author_id': _uid,
        'body': body,
      });
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}

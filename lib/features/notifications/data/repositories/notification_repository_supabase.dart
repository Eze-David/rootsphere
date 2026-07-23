import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';

/// Supabase-backed [NotificationRepository]. See
/// supabase/migrations/20260722010000_notifications.sql for the table, RLS,
/// and the triggers that actually create rows.
class NotificationRepositorySupabase implements NotificationRepository {
  NotificationRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _notifications => _client.from('notifications');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Stream<List<AppNotification>> watchNotifications() {
    if (_uid.isEmpty) return Stream<List<AppNotification>>.value(const []);
    return _notifications
        .stream(primaryKey: <String>['id'])
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }

  @override
  Future<void> markRead(String id) async {
    try {
      await _notifications.update(<String, dynamic>{'read': true}).eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> markAllRead() async {
    if (_uid.isEmpty) return;
    try {
      await _notifications
          .update(<String, dynamic>{'read': true})
          .eq('user_id', _uid)
          .eq('read', false);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}

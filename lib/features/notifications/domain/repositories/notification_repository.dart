import '../entities/app_notification.dart';

/// Persistence contract for in-app notifications. Rows are created
/// server-side (see supabase/migrations/20260722010000_notifications.sql) —
/// this only ever reads and marks-as-read.
abstract class NotificationRepository {
  /// Streams the signed-in user's notifications, newest first.
  Stream<List<AppNotification>> watchNotifications();

  Future<void> markRead(String id);

  Future<void> markAllRead();
}

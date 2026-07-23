import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';

/// Offline/no-Supabase fallback. Every notification type is inherently
/// about another user's activity (someone else editing a shared tree,
/// claiming your request, joining, donating) — none of that is possible
/// without a backend, so this is always empty rather than a fake local
/// simulation of multi-user activity.
class NotificationRepositoryLocal implements NotificationRepository {
  @override
  Stream<List<AppNotification>> watchNotifications() =>
      Stream<List<AppNotification>>.value(const <AppNotification>[]);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}

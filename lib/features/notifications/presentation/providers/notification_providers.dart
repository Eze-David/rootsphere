import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/notification_repository_local.dart';
import '../../data/repositories/notification_repository_supabase.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return NotificationRepositorySupabase(SupabaseConfig.client);
  }
  return NotificationRepositoryLocal();
});

/// The signed-in user's notifications, newest first. Re-subscribes whenever
/// the signed-in user changes (autoDispose + watching authStateProvider) so
/// switching accounts doesn't keep streaming the previous user's rows — see
/// the same fix applied to activeTreeIdProvider and friends.
final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(notificationRepositoryProvider).watchNotifications();
  },
);

/// Unread count for the bell icon's badge.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final List<AppNotification> notifications =
      ref.watch(notificationsProvider).value ?? const <AppNotification>[];
  return notifications.where((n) => !n.read).length;
});

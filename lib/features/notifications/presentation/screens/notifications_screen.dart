import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/app_notification.dart';
import '../providers/notification_providers.dart';

/// Full list behind the Home screen's bell icon.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AppNotification>> notificationsAsync = ref.watch(
      notificationsProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                ref.read(notificationRepositoryProvider).markAllRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  "You're all caught up. Activity from shared trees and "
                  "opportunities will show up here.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final AppNotification n = notifications[index];
              return _NotificationTile(
                notification: n,
                onTap: () => _handleTap(context, ref, n),
              );
            },
          );
        },
      ),
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref, AppNotification n) {
    if (!n.read) {
      ref.read(notificationRepositoryProvider).markRead(n.id);
    }
    switch (n.type) {
      case NotificationType.treeActivity:
        if (n.personId != null) {
          context.push('${AppRoutes.person}/${n.personId}');
        }
      case NotificationType.opportunityClaimed:
      case NotificationType.opportunityVerified:
      case NotificationType.donationReceived:
      case NotificationType.opportunityCompanyApproved:
      case NotificationType.opportunityCompanyRejected:
        context.go(
          n.opportunityId == null
              ? AppRoutes.collab
              : '${AppRoutes.collab}?openId=${n.opportunityId}',
        );
      case NotificationType.opportunityCompanyRequest:
        // A root-level pushed screen (like role-verification-review), not a
        // bottom-tab shell route — push (not go) so it gets a back button.
        context.push(
          n.opportunityId == null
              ? AppRoutes.companyRequests
              : '${AppRoutes.companyRequests}?openId=${n.opportunityId}',
        );
      case NotificationType.opportunitySubmitted:
        context.push(
          n.opportunityId == null
              ? AppRoutes.submissionReview
              : '${AppRoutes.submissionReview}?openId=${n.opportunityId}',
        );
      case NotificationType.treeMemberJoined:
        context.go(AppRoutes.profile);
      case NotificationType.unknown:
        break;
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.type) {
    NotificationType.treeActivity => Icons.park_outlined,
    NotificationType.opportunityClaimed => Icons.handshake_outlined,
    NotificationType.opportunityVerified => Icons.verified_outlined,
    NotificationType.donationReceived => Icons.favorite_outline,
    NotificationType.treeMemberJoined => Icons.group_add_outlined,
    NotificationType.opportunityCompanyRequest => Icons.apartment_outlined,
    NotificationType.opportunitySubmitted => Icons.fact_check_outlined,
    NotificationType.opportunityCompanyApproved => Icons.thumb_up_outlined,
    NotificationType.opportunityCompanyRejected => Icons.error_outline,
    NotificationType.unknown => Icons.notifications_none,
  };

  /// "Just now" / "5m ago" / "3h ago" / "2d ago" / a short date beyond that.
  String get _relativeTime {
    final Duration diff = DateTime.now().difference(notification.createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final DateTime d = notification.createdAt;
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Material(
      color: notification.read
          ? Colors.transparent
          : AppColors.surfaceMuted.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceMuted,
                child: Icon(_icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      notification.title,
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(notification.body, style: text.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notification.read)
                Container(
                  margin: const EdgeInsets.only(top: 4, left: 8),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.sunGold,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/support_message.dart';
import '../providers/support_message_providers.dart';
import 'support_message_thread_screen.dart';

/// Support message inbox (Profile ▸ Support). For an admin this lists
/// everyone's messages; for anyone else RLS narrows it to just their own —
/// see [supportMessagesProvider] and
/// supabase/migrations/20260724020000_support_messages.sql.
class SupportMessagesScreen extends ConsumerWidget {
  const SupportMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SupportMessage>> messagesAsync = ref.watch(
      supportMessagesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Support messages')),
      body: messagesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (messages) {
          if (messages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No support messages yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final SupportMessage m = messages[index];
              return _MessageCard(
                message: m,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportMessageThreadScreen(message: m),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.onTap});

  final SupportMessage message;
  final VoidCallback onTap;

  bool get _resolved => message.status == SupportMessageStatus.resolved;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      message.email,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _resolved
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.sunGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      _resolved ? 'Resolved' : 'Open',
                      style: text.labelSmall?.copyWith(
                        color: _resolved
                            ? AppColors.success
                            : AppColors.sunGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _relativeTime(message.createdAt),
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Just now" / "5m ago" / "3h ago" / "2d ago" / a short date beyond that.
  String _relativeTime(DateTime createdAt) {
    final Duration diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

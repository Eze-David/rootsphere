import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/offline_providers.dart';
import '../../core/offline/outbox.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/archive/presentation/providers/archive_providers.dart';
import '../../features/tree/presentation/providers/tree_providers.dart';

/// Thin strip above the bottom navigation saying the app is offline and/or
/// how many changes (family tree + Digital Records Repository) are still
/// waiting to sync. Hidden when there's nothing to say.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider).value ?? true;
    final SyncStatus tree =
        ref.watch(treeSyncStatusProvider).value ?? const SyncStatus();
    final SyncStatus archive =
        ref.watch(archiveSyncStatusProvider).value ?? const SyncStatus();
    final SyncStatus sync = SyncStatus(
      pending: tree.pending + archive.pending,
      error: tree.error ?? archive.error,
    );
    final ColorScheme colors = Theme.of(context).colorScheme;

    final String changes = sync.pending == 1
        ? '1 change'
        : '${sync.pending} changes';

    final (IconData icon, String message, bool isError)? content;
    if (sync.error != null) {
      content = (
        Icons.error_outline,
        "A change made offline couldn't be saved: ${sync.error}",
        true,
      );
    } else if (!online) {
      content = (
        Icons.cloud_off_outlined,
        sync.pending > 0
            ? "You're offline. $changes will sync when you reconnect."
            : "You're offline. Your family tree and records still work; "
                  'edits sync when you reconnect.',
        false,
      );
    } else if (sync.pending > 0) {
      content = (Icons.sync, 'Syncing $changes…', false);
    } else {
      content = null;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: content == null
          ? const SizedBox(width: double.infinity)
          : Material(
              color: content.$3
                  ? colors.errorContainer
                  : colors.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      content.$1,
                      size: 18,
                      color: content.$3
                          ? colors.onErrorContainer
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        content.$2,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: content.$3
                              ? colors.onErrorContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (content.$3)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        color: colors.onErrorContainer,
                        tooltip: 'Dismiss',
                        onPressed: () {
                          ref.read(offlineTreeRepositoryProvider)?.clearError();
                          ref
                              .read(offlineArchiveRepositoryProvider)
                              ?.clearError();
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/error_retry_view.dart';
import '../../domain/entities/archive_access_request.dart';
import '../../domain/entities/archive_record.dart';
import '../providers/archive_providers.dart';

/// Admin queue of Permission-tier access requests — same list/approve/reject
/// pattern as role_verification_review_screen.dart. Approving a request
/// flips the underlying record to Online for everyone (handled server-side
/// by the notify_archive_access_reviewed() trigger).
class ArchiveAccessRequestsTab extends ConsumerWidget {
  const ArchiveAccessRequestsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ArchiveAccessRequest>> pendingAsync = ref.watch(
      pendingArchiveAccessRequestsProvider,
    );

    return pendingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetryView(
        error: e,
        onRetry: () => ref.invalidate(pendingArchiveAccessRequestsProvider),
      ),
      data: (pending) {
        if (pending.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'No pending access requests.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: pending.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _RequestCard(request: pending[index]),
        );
      },
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request});
  final ArchiveAccessRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<void> _review(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(archiveAccessRequestRepositoryProvider)
          .review(widget.request.id, approve: approve);
      ref.invalidate(pendingArchiveAccessRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve ? 'Approved — record is now Online.' : 'Rejected.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ArchiveRecord> all =
        ref.watch(archiveRecordsProvider).value ?? const <ArchiveRecord>[];
    ArchiveRecord? record;
    for (final ArchiveRecord r in all) {
      if (r.id == widget.request.recordId) {
        record = r;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            record?.displayTitle ?? 'Unknown record',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (record != null && record.collection.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              record.collection,
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _review(false),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _review(true),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

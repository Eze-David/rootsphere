import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/error_retry_view.dart';
import '../../domain/entities/archive_record.dart';
import '../providers/archive_providers.dart';

/// Admin queue of records submitted for review (mockup step 3) — approving
/// publishes the record and makes it public; rejecting sends it back with a
/// note. RLS blocks all of this for anyone but an admin regardless of what
/// the UI shows.
class ArchiveReviewQueueTab extends ConsumerWidget {
  const ArchiveReviewQueueTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ArchiveRecord>> recordsAsync = ref.watch(
      archiveRecordsProvider,
    );

    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetryView(
        error: e,
        onRetry: () => ref.invalidate(archiveRecordsProvider),
      ),
      data: (_) {
        final List<ArchiveRecord> pending = ref.watch(
          archiveRecordsPendingReviewProvider,
        );
        if (pending.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'No records pending review.',
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
          itemBuilder: (context, index) => _PendingCard(record: pending[index]),
        );
      },
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({required this.record});
  final ArchiveRecord record;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _busy = false;

  Future<void> _review(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(archiveRepositoryProvider)
          .review(widget.record.id, approved: approve);
      ref.invalidate(archiveRecordsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Published.' : 'Rejected.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ArchiveRecord r = widget.record;
    final List<String> meta = <String>[
      if (r.collection.isNotEmpty) r.collection,
      if (r.stateRegion.isNotEmpty) r.stateRegion,
      if (r.dateRangeLabel.isNotEmpty) r.dateRangeLabel,
    ];

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
            r.displayTitle,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              meta.join(' · '),
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          if ((r.description ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(r.description!, style: text.bodyMedium),
          ],
          if (r.files.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${r.files.length} file${r.files.length == 1 ? '' : 's'} attached',
              style: text.bodySmall,
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
                      : const Text('Approve & publish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

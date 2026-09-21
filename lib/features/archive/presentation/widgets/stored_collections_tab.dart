import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/error_retry_view.dart';
import '../../../records/domain/entities/record.dart';
import '../../domain/entities/archive_record.dart';
import '../providers/archive_providers.dart';
import 'archive_record_detail_sheet.dart';

/// Browse/search every catalogued record regardless of status (mockup's
/// "Stored collections" tab, covering steps 4–5: Catalogue + Search).
class StoredCollectionsTab extends ConsumerWidget {
  const StoredCollectionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ArchiveRecord>> recordsAsync = ref.watch(
      archiveRecordsProvider,
    );

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _SearchField(),
        ),
        Expanded(
          child: recordsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetryView(
              error: e,
              onRetry: () => ref.invalidate(archiveRecordsProvider),
            ),
            data: (_) {
              final List<ArchiveRecord> filtered = ref.watch(
                filteredArchiveRecordsProvider,
              );
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No stored records yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) => _RecordCard(
                  record: filtered[index],
                  onTap: () async {
                    final ArchiveDetailAction? action =
                        await showArchiveRecordDetail(
                          context,
                          ref,
                          filtered[index],
                        );
                    if (action == ArchiveDetailAction.continueEditing) {
                      ref
                          .read(archiveRecordBeingEditedProvider.notifier)
                          .state = filtered[index];
                      if (context.mounted) {
                        DefaultTabController.of(context).animateTo(0); // Add record
                      }
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(archiveSearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(archiveSearchProvider.notifier).state = v,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search collection, place, keywords…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  ref.read(archiveSearchProvider.notifier).state = '';
                  setState(() {});
                },
              ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onTap});
  final ArchiveRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> meta = <String>[
      if (record.collection.isNotEmpty) record.collection,
      if (record.stateRegion.isNotEmpty) record.stateRegion,
      if (record.dateRangeLabel.isNotEmpty) record.dateRangeLabel,
    ];

    final String? indexedLabel = record.files.isEmpty
        ? null
        : (record.searchText ?? '').isNotEmpty
        ? 'Indexed'
        : 'Not indexed';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(record.type.icon, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          record.displayTitle,
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _StatusBadge(status: record.reviewStatus),
                    ],
                  ),
                  if (meta.isNotEmpty || indexedLabel != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        ...meta,
                        '${record.files.length} file${record.files.length == 1 ? '' : 's'}',
                        if (indexedLabel != null) indexedLabel,
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      _AccessBadge(status: record.accessStatus),
                      if (record.recordRef != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            record.recordRef!,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.status});
  final ArchiveAccessStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ArchiveReviewStatus status;

  Color _color() {
    switch (status) {
      case ArchiveReviewStatus.draft:
        return AppColors.textTertiary;
      case ArchiveReviewStatus.pendingReview:
        return AppColors.sunGold;
      case ArchiveReviewStatus.published:
        // AppColors.primary is a near-black espresso brown made for
        // light-mode surfaces — unreadable as badge text on a dark
        // background. success/statusVerified (green) is the app's existing
        // "approved and live" accent and has contrast in both themes.
        return AppColors.success;
      case ArchiveReviewStatus.rejected:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

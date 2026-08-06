import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/historical_record.dart';
import '../../domain/entities/record.dart';

/// A hit from the external (FamilySearch-style) historical records provider.
/// Shared by the per-category search screens and the main records library
/// search.
class HistoricalResultCard extends StatelessWidget {
  const HistoricalResultCard({
    super.key,
    required this.hit,
    required this.saved,
    required this.onSave,
    required this.onOpen,
  });

  final HistoricalRecord hit;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    hit.type.icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(hit.name, style: text.titleMedium),
                      if (hit.subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(hit.subtitle, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                if ((hit.source ?? '').isNotEmpty) SourceBadge(hit.source!),
                const Spacer(),
                if (onOpen != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View'),
                  ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: saved ? null : onSave,
                  icon: Icon(saved ? Icons.check : Icons.add, size: 16),
                  label: Text(saved ? 'Saved' : 'Save to tree'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small pill showing which provider a result came from.
class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.public, size: 12, color: text.bodyMedium?.color),
          const SizedBox(width: 4),
          Text(source, style: text.labelSmall),
        ],
      ),
    );
  }
}

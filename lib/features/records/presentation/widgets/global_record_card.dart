import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/global_record_match.dart';
import '../../domain/entities/record.dart';

/// A community (cross-tree, unattached) record match: "View" opens the file
/// directly, "Save" copies it into the signed-in user's own tree. Shared by
/// the per-category search screens and the main records library search, so
/// both reach the same community records the same way.
class GlobalRecordCard extends StatelessWidget {
  const GlobalRecordCard({
    super.key,
    required this.match,
    required this.saved,
    required this.onSave,
    required this.onOpen,
  });

  final GlobalRecordMatch match;
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
                    match.type.icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(match.displayTitle, style: text.titleMedium),
                      if (match.subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(match.subtitle, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
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
                  label: Text(saved ? 'Saved' : 'Save to my records'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

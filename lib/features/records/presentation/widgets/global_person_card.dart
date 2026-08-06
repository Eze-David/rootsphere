import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/global_person_match.dart';

/// A cross-tree person match: offers to join that tree. Shared by the
/// per-category search screens and the main records library search.
class GlobalPersonCard extends StatelessWidget {
  const GlobalPersonCard({
    super.key,
    required this.match,
    required this.joining,
    required this.onJoin,
  });

  final GlobalPersonMatch match;
  final bool joining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
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
                Icons.travel_explore,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(match.fullName, style: text.titleMedium),
                  if (match.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(match.subtitle, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: joining ? null : onJoin,
              child: joining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join tree'),
            ),
          ],
        ),
      ),
    );
  }
}

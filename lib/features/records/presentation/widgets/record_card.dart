import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../domain/entities/record.dart';

/// A single row in the records library, matching the mockup: a rounded type
/// icon (or image thumbnail) beside the title and "repository · year" subtitle.
class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.record, required this.onTap});

  final Record record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      // No explicit color/border — Card already picks up the theme's
      // cardTheme (correctly dark in dark mode); overriding it here with a
      // fixed light color was the bug.
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              _Thumbnail(record: record),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      record.displayTitle,
                      style: text.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (record.subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        record.subtitle,
                        style: text.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.record});
  final Record record;

  @override
  Widget build(BuildContext context) {
    const double size = 52;
    if (record.hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: AdaptiveImage(
          reference: record.fileUrl!,
          width: size,
          height: size,
        ),
      );
    }
    final ThemeData theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: theme.dividerColor),
      ),
      alignment: Alignment.center,
      child: Icon(record.type.icon, color: theme.colorScheme.primary, size: 24),
    );
  }
}

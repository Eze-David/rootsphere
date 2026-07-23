import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/hint.dart';

/// A single confidence-ranked hint with an accept/dismiss flow.
class HintCard extends StatelessWidget {
  const HintCard({
    super.key,
    required this.hint,
    required this.onAccept,
    required this.onDismiss,
    this.onTap,
    this.busy = false,
  });

  final Hint hint;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(hint.type.icon,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(hint.title,
                            style: text.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(hint.type.label, style: text.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _ConfidenceChip(confidence: hint.confidence),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(hint.description, style: text.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  if (hint.source == 'ai')
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.auto_awesome,
                              size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text('AI', style: text.labelSmall),
                        ],
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: busy ? null : onDismiss,
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: busy ? null : onAccept,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      backgroundColor: AppColors.primary,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Text(
                            hint.type == HintType.duplicate ? 'Review' : 'Accept',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});
  final int confidence;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = confidence >= 80
        ? AppColors.statusVerified
        : confidence >= 60
            ? AppColors.statusOpen
            : AppColors.statusClaimed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        '$confidence%',
        style: text.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

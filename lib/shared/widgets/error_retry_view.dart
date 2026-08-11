import 'package:flutter/material.dart';

import '../../core/error/failure.dart';
import '../../core/theme/app_spacing.dart';

/// Standard "something failed" state for `AsyncValue.when(error: ...)`
/// builders: a friendly English message (never a raw exception dump) plus,
/// when [onRetry] is given, a Retry button so a dropped connection doesn't
/// leave someone stuck staring at a dead screen.
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    super.key,
    required this.error,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  final Object error;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              friendlyErrorMessage(error),
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

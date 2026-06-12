import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';

/// One-time onboarding screen shown on first launch, built around the
/// Rootsphere logo (brief §5.1 — entry experience).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;

    Future<void> getStarted() async {
      await ref.read(onboardingCompleteProvider.notifier).complete();
      if (context.mounted) context.go(AppRoutes.auth);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Spacer(),
                  Image.asset(
                    'assets/images/logo.png',
                    width: 240,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Rootsphere',
                    style: text.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapMd,
                  Text(
                    'Discover, document and grow\nyour family history',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: getStarted,
                    child: const Text('Get started'),
                  ),
                  AppSpacing.gapMd,
                  TextButton(
                    onPressed: getStarted,
                    child: Text(
                      'I already have an account',
                      style: text.labelLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

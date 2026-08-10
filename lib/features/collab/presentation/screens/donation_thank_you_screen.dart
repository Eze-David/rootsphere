import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';

/// Where Paystack redirects the browser after checkout (`callback_url`) —
/// a real page on our own domain rather than a Supabase Edge Function URL
/// (see [AppRoutes.donationThankYou]). Paystack doesn't distinguish
/// success/cancel via this redirect; the donation is actually confirmed
/// server-side by the `paystack-webhook` function, not by this page.
class DonationThankYouScreen extends StatelessWidget {
  const DonationThankYouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.favorite,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Thank you!',
                    style: text.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Thanks for supporting this research. If your payment '
                    "went through, it'll be confirmed and show up shortly.",
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: const Text('Return to Rootsphere'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_mode_provider.dart';
import 'donation_details_screen.dart';

/// The first step of the full donation wizard — reachable from the landing
/// page's "Support Our Mission" banner. A signed-in visitor sees a single
/// "Donate Now" continue button; a signed-out one is offered both "Continue
/// as Guest" (donates without an account, a receipt goes to their email) and
/// "Sign In & Continue" (attaches the donation to an existing account's
/// history). Opportunity-specific "Support this research" asks keep using
/// the lighter [showDonateDialog] bottom sheet — this longer flow is only
/// for the general, foundation-wide ask.
class DonationWelcomeScreen extends ConsumerWidget {
  const DonationWelcomeScreen({super.key});

  void _continue(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DonationDetailsScreen()),
    );
  }

  Future<void> _signInThenContinue(BuildContext context, WidgetRef ref) async {
    ref.read(authInitialModeProvider.notifier).state = false;
    context.push(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool signedIn = Supabase.instance.client.auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
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
                    'Your Support Helps Preserve Family Heritage',
                    style: text.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'By supporting RootSphere, you are helping families '
                    'discover their roots, preserve precious memories, '
                    'document family histories, and make them available for '
                    'generations yet to come.\n\nEvery contribution, no '
                    'matter the amount, makes a difference.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (signedIn) ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _continue(context),
                        child: const Text('Donate Now'),
                      ),
                    ),
                  ] else ...<Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'No Account? No Problem.',
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'You can support RootSphere without creating an '
                            'account. Simply continue as a guest, provide '
                            'the information needed for your receipt, and '
                            'complete your contribution securely.',
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => _continue(context),
                              child: const Text('Continue as Guest'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Welcome Back', style: text.titleMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Sign in to make your contribution and keep '
                            'your donation receipts and giving history '
                            'conveniently connected to your RootSphere '
                            'account.',
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () =>
                                  _signInThenContinue(context, ref),
                              child: const Text('Sign In & Continue'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

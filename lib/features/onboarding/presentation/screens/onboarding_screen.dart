import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_mode_provider.dart';
import '../../../auth/presentation/screens/legal_document_screen.dart';
import '../../../collab/presentation/widgets/donate_dialog.dart';
import '../providers/onboarding_provider.dart';

/// The marketing landing page shown at rootsphere.ink before anyone signs
/// in — a real scrolling website (hero, features, how-it-works, footer)
/// rather than the old swipeable phone-style carousel, since this is a web
/// app's actual front door. "Get started"/"Sign in" both complete onboarding
/// and hand off into the existing auth flow.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  Future<void> _enter(
    BuildContext context,
    WidgetRef ref, {
    required bool signUp,
  }) async {
    ref.read(authInitialModeProvider.notifier).state = signUp;
    await ref.read(onboardingCompleteProvider.notifier).complete();
    if (context.mounted) context.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isWide = MediaQuery.sizeOf(context).width > 800;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _Hero(
            isWide: isWide,
            onGetStarted: () => _enter(context, ref, signUp: true),
            onSignIn: () => _enter(context, ref, signUp: false),
            onDonate: () => showDonateDialog(context, ref),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 80 : AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            child: Column(
              children: <Widget>[
                _FeaturesSection(isWide: isWide),
                const SizedBox(height: AppSpacing.xxl),
                _HowItWorksSection(isWide: isWide),
                const SizedBox(height: AppSpacing.xxl),
                _CtaBanner(
                  onGetStarted: () => _enter(context, ref, signUp: true),
                ),
              ],
            ),
          ),
          const _Footer(),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.isWide,
    required this.onGetStarted,
    required this.onSignIn,
    required this.onDonate,
  });

  final bool isWide;
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  final VoidCallback onDonate;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SizedBox(
        height: isWide ? 640 : 560,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset('assets/images/onboarding -image.jpg', fit: BoxFit.cover),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        Image.asset(
                          'assets/images/logo.png',
                          width: 40,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Rootsphere',
                          style: text.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: onSignIn,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Discover, document and grow\nyour family history',
                                textAlign: TextAlign.center,
                                style:
                                    (isWide
                                            ? text.displayLarge
                                            : text.displayMedium)
                                        ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                'Build a living family tree, collect the records that '
                                'prove it, and pass your history down — together.',
                                textAlign: TextAlign.center,
                                style: text.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: AppSpacing.md,
                                runSpacing: AppSpacing.md,
                                children: <Widget>[
                                  SizedBox(
                                    width: 200,
                                    child: FilledButton(
                                      onPressed: onGetStarted,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.primary,
                                      ),
                                      child: const Text('Get started'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: OutlinedButton(
                                      onPressed: onSignIn,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: Colors.white,
                                        ),
                                      ),
                                      child: const Text('Sign in'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _DonateLink(onTap: onDonate),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets a visitor support Rootsphere without creating an account — shown on
/// the landing page (rather than the auth screen) since it's meant as an
/// alternative to signing up at all, not a step within that flow.
class _DonateLink extends StatefulWidget {
  const _DonateLink({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_DonateLink> createState() => _DonateLinkState();
}

class _DonateLinkState extends State<_DonateLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = _hovering
        ? AppColors.sunGoldLight
        : Colors.white.withValues(alpha: 0.85);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // Scales down rather than overflowing on the narrowest widths,
        // where the icon + full label is a shade too wide.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.favorite_border, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Donate to support family history in Africa',
                style: text.labelLarge?.copyWith(
                  color: color,
                  decoration: _hovering ? TextDecoration.underline : null,
                  decorationColor: AppColors.sunGoldLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature {
  const _Feature(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}

const List<_Feature> _features = <_Feature>[
  _Feature(
    Icons.account_tree_outlined,
    'Build your family tree',
    'Add ancestors and descendants, link spouses and children, '
        'and see it all laid out generation by generation.',
  ),
  _Feature(
    Icons.description_outlined,
    'Collect historical records',
    'Upload birth certificates, marriage registers, cemetery records '
        'and more — searchable and OCR\'d automatically.',
  ),
  _Feature(
    Icons.diversity_3_outlined,
    'Collaborate with family',
    'Invite relatives to your tree, assign research tasks, '
        'and verify each other\'s contributions.',
  ),
  _Feature(
    Icons.auto_awesome_outlined,
    'AI research assistant',
    'Get suggested ancestors, generated timelines, and research '
        'recommendations powered by Claude.',
  ),
];

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required this.isWide});
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(
        children: <Widget>[
          Text(
            'Everything you need to trace your roots',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: <Widget>[
              for (final _Feature f in _features)
                SizedBox(
                  width: isWide ? 240 : double.infinity,
                  child: _FeatureCard(feature: f),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              feature.icon,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            feature.title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(feature.description, style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _Step {
  const _Step(this.number, this.title, this.description);
  final String number;
  final String title;
  final String description;
}

const List<_Step> _steps = <_Step>[
  _Step(
    '1',
    'Create your tree',
    'Start with yourself and add the people you already know.',
  ),
  _Step(
    '2',
    'Invite family & upload records',
    'Bring relatives on board and attach the documents that back up each name.',
  ),
  _Step(
    '3',
    'Discover your history',
    'Let the research assistant suggest ancestors and fill in the gaps.',
  ),
];

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection({required this.isWide});
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> stepContent = <Widget>[
      for (final _Step s in _steps)
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? AppSpacing.md : 0,
            vertical: isWide ? 0 : AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary,
                child: Text(
                  s.number,
                  style: const TextStyle(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                s.title,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.description,
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Column(
        children: <Widget>[
          Text('How it works', textAlign: TextAlign.center, style: text.headlineSmall),
          const SizedBox(height: AppSpacing.xxl),
          if (isWide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final Widget w in stepContent) Expanded(child: w),
                ],
              ),
            )
          else
            Column(children: stepContent),
        ],
      ),
    );
  }
}

class _CtaBanner extends StatelessWidget {
  const _CtaBanner({required this.onGetStarted});
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 900),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'Start building your family tree today',
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Free to get started. No credit card required.',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 220,
            child: FilledButton(
              onPressed: onGetStarted,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              child: const Text('Get started'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          Text('© ${DateTime.now().year} Rootsphere', style: text.bodySmall),
          TextButton(
            onPressed: () =>
                _open(context, const LegalDocumentScreen.termsOfService()),
            child: const Text('Terms of Service'),
          ),
          TextButton(
            onPressed: () =>
                _open(context, const LegalDocumentScreen.privacyPolicy()),
            child: const Text('Privacy Policy'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';

class _Slide {
  const _Slide({
    required this.asset,
    required this.title,
    required this.subtitle,
    this.showLogo = false,
  });

  final String asset;
  final String title;
  final String subtitle;
  final bool showLogo;
}

const List<_Slide> _slides = <_Slide>[
  _Slide(
    asset: 'assets/images/onboarding -image.png',
    title: 'Rootsphere',
    subtitle: 'Discover, document and grow\nyour family history',
    showLogo: true,
  ),
  _Slide(
    asset: 'assets/images/a-man-teaching -his-son.png',
    title: 'Trace your roots',
    subtitle:
        'Build a living family tree and uncover\nthe stories behind every name.',
  ),
  _Slide(
    asset: 'assets/images/a-woman-teaching-her.png',
    title: 'Preserve it together',
    subtitle:
        'Collect records, share memories, and pass\nyour history down as a family.',
  ),
];

/// One-time onboarding carousel shown on first launch (brief §5.1 — entry
/// experience): a swipeable set of slides ending in "Get started".
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _getStarted() async {
    await ref.read(onboardingCompleteProvider.notifier).complete();
    if (mounted) context.go(AppRoutes.auth);
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _getStarted();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isLast = _page == _slides.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (int index) => setState(() => _page = index),
              itemBuilder: (_, int index) =>
                  _SlideView(slide: _slides[index], text: text),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int i = 0; i < _slides.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            width: i == _page ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (isLast)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _getStarted,
                          child: const Text('Get started'),
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          TextButton(
                            onPressed: _getStarted,
                            child: Text(
                              'Skip',
                              style: text.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                            ),
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.text});

  final _Slide slide;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(slide.asset, fit: BoxFit.cover),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.85),
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (slide.showLogo) ...<Widget>[
                      Image.asset(
                        'assets/images/logo.png',
                        width: 200,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                    Text(
                      slide.title,
                      style: text.displayMedium?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapMd,
                    Text(
                      slide.subtitle,
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

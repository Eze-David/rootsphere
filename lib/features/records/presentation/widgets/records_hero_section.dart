import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'african_sunburst_painter.dart';

/// Hero header for the historical-records search screen.
///
/// Uses a warm cream background, a large serif headline, a subtitle, and a
/// decorative African sunburst. A family photo asset is used if present;
/// otherwise a sunburst-only fallback is shown.
class RecordsHeroSection extends StatelessWidget {
  const RecordsHeroSection({super.key, this.familyImageAsset});

  /// Optional asset path for a family photo to overlay on the sunburst.
  final String? familyImageAsset;

  static const String defaultFamilyAsset =
      'assets/images/records_hero_family.png';

  @override
  Widget build(BuildContext context) {
    final String asset = familyImageAsset ?? defaultFamilyAsset;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isWide = MediaQuery.of(context).size.width > 600;

    return Container(
      color: AppColors.heroCream,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: _Headline(text: text)),
                const SizedBox(width: AppSpacing.xl),
                _HeroVisual(asset: asset),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Headline(text: text),
                const SizedBox(height: AppSpacing.xl),
                Center(child: _HeroVisual(asset: asset)),
              ],
            ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Find your African\nancestors',
          style: GoogleFonts.playfairDisplay(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: AppColors.heroText,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Search for names in African records, family trees,\ncemeteries, and oral histories.',
          style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          const AfricanSunburst(size: 260, rayCount: 36),
          _FamilyImage(asset: asset),
        ],
      ),
    );
  }
}

class _FamilyImage extends StatelessWidget {
  const _FamilyImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: 180,
      height: 180,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _FallbackFamily(),
    );
  }
}

class _FallbackFamily extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.sunGold.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.family_restroom,
        size: 64,
        color: AppColors.sunGold.withValues(alpha: 0.75),
      ),
    );
  }
}

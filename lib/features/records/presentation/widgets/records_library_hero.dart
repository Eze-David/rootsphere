import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_spacing.dart';

/// Hero banner used by the Records library and search screens.
///
/// A dark overlay sits on top of the supplied photo so the white text remains
/// readable on both mobile and desktop. The form/white card is intentionally
/// left to the consuming screen.
class RecordsLibraryHero extends StatelessWidget {
  const RecordsLibraryHero({
    super.key,
    required this.asset,
    required this.title,
    this.subtitle,
  });

  final String asset;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width > 700;

    return Container(
      height: isWide ? 360 : 320,
      width: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(asset),
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        ),
      ),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.72),
              Colors.black.withValues(alpha: 0.48),
              Colors.black.withValues(alpha: 0.12),
            ],
            stops: const <double>[0.0, 0.55, 1.0],
          ),
        ),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: _Headline(title: title, subtitle: subtitle),
                  ),
                  const Expanded(flex: 5, child: SizedBox.shrink()),
                ],
              )
            : _Headline(title: title, subtitle: subtitle),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: Colors.white,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

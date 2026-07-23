import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/legal_document.dart';

/// Full-screen reader for the Terms of Service or Privacy Policy — shared by
/// the sign-up agreement checkbox and Profile ▸ Support.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.intro,
    required this.sections,
  });

  const LegalDocumentScreen.termsOfService({super.key})
      : title = 'Terms of Service',
        intro = LegalDocuments.termsOfServiceIntro,
        sections = LegalDocuments.termsOfService;

  const LegalDocumentScreen.privacyPolicy({super.key})
      : title = 'Privacy Policy',
        intro = LegalDocuments.privacyPolicyIntro,
        sections = LegalDocuments.privacyPolicy;

  final String title;
  final String intro;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Text(
            'Last updated: ${LegalDocuments.lastUpdated}',
            style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(intro, style: text.bodyLarge),
          for (final LegalSection section in sections) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            Text(
              section.heading,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(section.body, style: text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

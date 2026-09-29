import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/screens/legal_document_screen.dart';
import '../../../collab/presentation/screens/donation_welcome_screen.dart';

/// A dedicated "About" page — logo, description, version, and quick links
/// into the legal/foundation pages already reachable from Profile ▸ Support,
/// gathered in one place instead of a small dialog.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Kept in sync with pubspec.yaml's `version:` by hand (no extra
  // package_info_plus dependency just to read a value with app-store-listing
  // stakes low enough that a manual bump alongside the pubspec is fine).
  static const String _version = '1.1.1';

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Center(
            child: Image.asset(
              'assets/images/rootsphere-logo-espresso-v6-cropped.png',
              width: 96,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              'RootSphere',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Discover, document and grow your family history.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'RootSphere is a family history app built around African '
            'ancestry research. Build an interactive family tree across '
            'ancestors, descendants, and pedigree views; collect birth, '
            'marriage, death, baptism, census, and other records in one '
            'place with OCR and an AI research assistant; and collaborate '
            'with the community to find, index, and verify records for '
            'opportunities near you.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              'Version $_version',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _AboutLinkTile(
            icon: Icons.diversity_3_outlined,
            label: 'Our Foundation',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalDocumentScreen.ourFoundation(),
              ),
            ),
          ),
          _AboutLinkTile(
            icon: Icons.favorite_border,
            label: 'Donate',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DonationWelcomeScreen(),
              ),
            ),
          ),
          _AboutLinkTile(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalDocumentScreen.termsOfService(),
              ),
            ),
          ),
          _AboutLinkTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalDocumentScreen.privacyPolicy(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutLinkTile extends StatelessWidget {
  const _AboutLinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: onTap,
    );
  }
}

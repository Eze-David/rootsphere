import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/fullscreen_document_text_viewer.dart';
import '../../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../../shared/widgets/fullscreen_pdf_viewer.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/role_verification.dart';
import '../providers/role_verification_providers.dart';

const List<String> _imageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
];

String _extensionOf(String url) {
  final String path = Uri.tryParse(url)?.path ?? url;
  final int dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

Future<void> _openDocument(
  BuildContext context,
  String url,
  String title,
) async {
  final String ext = _extensionOf(url);
  if (_imageExtensions.contains(ext)) {
    await showFullscreenImage(context, url);
  } else if (ext == 'pdf') {
    await showFullscreenPdf(context, reference: url, title: title);
  } else {
    await showFullscreenDocumentText(context, url: url, title: title);
  }
}

/// Admin-only ("the company") queue of pending Finder/Indexer applications.
/// Reachable only if [isPlatformAdminProvider] is true — RLS blocks the
/// underlying query for anyone else regardless, this is just the UI gate.
class RoleVerificationReviewScreen extends ConsumerWidget {
  const RoleVerificationReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RoleVerification>> pendingAsync = ref.watch(
      pendingRoleVerificationsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Review applications')),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (pending) {
          if (pending.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No pending applications.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: pending.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) =>
                _ApplicationCard(application: pending[index]),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.application});
  final RoleVerification application;

  Future<void> _review(
    WidgetRef ref,
    BuildContext context,
    bool approve,
  ) async {
    await ref
        .read(roleVerificationRepositoryProvider)
        .review(application.id, approve: approve);
    // Realtime isn't guaranteed to push the change through promptly (same
    // issue fixed for the opportunities board) — force a fresh fetch rather
    // than leaving this card to update on its own.
    ref.invalidate(pendingRoleVerificationsProvider);
    ref.invalidate(myRoleVerificationsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Approved.' : 'Rejected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  application.applicantName,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _RoleBadge(role: application.role),
            ],
          ),
          if (application.applicantEmail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              application.applicantEmail,
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (application.applicantPhone.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              application.applicantPhone,
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          if ((application.note ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(application.note!, style: text.bodyMedium),
          ],
          if (application.governmentIdUrl != null ||
              application.documentUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                if (application.governmentIdUrl != null)
                  ActionChip(
                    avatar: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('Government ID'),
                    onPressed: () => _openDocument(
                      context,
                      application.governmentIdUrl!,
                      'Government ID',
                    ),
                  ),
                for (int i = 0; i < application.documentUrls.length; i++)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text('Certificate ${i + 1}'),
                    onPressed: () => _openDocument(
                      context,
                      application.documentUrls[i],
                      'Certificate ${i + 1}',
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _review(ref, context, false),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => _review(ref, context, true),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final CollaborationRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        role.label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

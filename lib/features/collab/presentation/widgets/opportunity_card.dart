import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/role_verification_providers.dart';

/// A small pill showing an opportunity's status (Open / Claimed / Verified),
/// shared by every place that lists or details an opportunity.
///
/// [changesRequested] overrides the label/colors to a distinct "Waiting for
/// changes" state — the underlying status is still `claimed` once the
/// company sends a submission back (so all the same claimed-stage actions
/// apply), but showing plain "Claimed" there would look identical to a
/// fresh, never-submitted claim.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.changesRequested = false,
  });
  final OpportunityStatus status;
  final bool changesRequested;

  Color get _color {
    if (changesRequested) return const Color(0xFFB26A00);
    switch (status) {
      case OpportunityStatus.open:
        return AppColors.sunGold;
      case OpportunityStatus.claimed:
        return AppColors.textSecondary;
      case OpportunityStatus.submitted:
        return AppColors.primary;
      case OpportunityStatus.companyApproved:
        return const Color(0xFF2E7D32);
      case OpportunityStatus.verified:
        return Colors.green;
    }
  }

  Color get _bg {
    if (changesRequested) return AppColors.sunGoldLight;
    switch (status) {
      case OpportunityStatus.open:
        return AppColors.sunGoldLight;
      case OpportunityStatus.claimed:
        return AppColors.cream;
      case OpportunityStatus.submitted:
        return AppColors.sunGoldLight;
      case OpportunityStatus.companyApproved:
        return const Color(0xFFE8F5E9);
      case OpportunityStatus.verified:
        return const Color(0xFFE8F5E9);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Text(
        changesRequested ? 'Waiting for changes' : status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A small pill marking an opportunity as sent directly to the company
/// rather than posted to the public board — only ever visible to the
/// requester or a platform admin (RLS hides the row from everyone else).
class CompanyRequestBadge extends StatelessWidget {
  const CompanyRequestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.apartment_outlined,
            size: 14,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            'Company request',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A card representing a single opportunity on the collaboration board.
class OpportunityCard extends StatelessWidget {
  const OpportunityCard({
    super.key,
    required this.opportunity,
    required this.currentUserId,
    this.onTap,
    this.onClaim,
    this.onContinueWork,
    this.onSubmitResult,
    this.onVerify,
    this.onUnclaim,
  });

  final CollaborationOpportunity opportunity;
  final String currentUserId;
  final VoidCallback? onTap;
  final VoidCallback? onClaim;

  /// Reopens the Finder/Indexer submission workspace — lets a claimer who
  /// left mid-way come back and resume rather than starting over.
  final VoidCallback? onContinueWork;
  final VoidCallback? onSubmitResult;
  final VoidCallback? onVerify;
  final VoidCallback? onUnclaim;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isRequester = opportunity.requesterId == currentUserId;
    final bool isClaimer = opportunity.claimerId == currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          opportunity.title,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (opportunity.description.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            opportunity.description,
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      StatusChip(
                        status: opportunity.status,
                        changesRequested: opportunity.changesRequested,
                      ),
                      if (opportunity.forCompany) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        const CompanyRequestBadge(),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  if (opportunity.location?.isNotEmpty ?? false)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          opportunity.location!,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        opportunity.requiredRole.icon,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        opportunity.requiredRole.label,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'By ${opportunity.requesterName}',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (opportunity.claimerId != null &&
                      !opportunity.isVerified) ...<Widget>[
                    Text(
                      'Attended to by ${opportunity.claimerName ?? 'someone'}',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ] else if (opportunity.isVerified) ...<Widget>[
                    Text(
                      'Verified',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              if (_showActions) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  children: <Widget>[
                    if (opportunity.isOpen && !isRequester)
                      TextButton.icon(
                        onPressed: onClaim,
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('Claim'),
                      ),
                    if (isClaimer && !opportunity.isVerified) ...<Widget>[
                      TextButton(
                        onPressed: onContinueWork,
                        child: const Text('Continue'),
                      ),
                      if (opportunity.isClaimed) ...<Widget>[
                        TextButton(
                          onPressed: onSubmitResult,
                          child: const Text('Submit result'),
                        ),
                        TextButton(
                          onPressed: onUnclaim,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textTertiary,
                          ),
                          child: const Text('Unclaim'),
                        ),
                      ],
                    ],
                    if (opportunity.isCompanyApproved &&
                        isRequester &&
                        !isClaimer)
                      TextButton.icon(
                        onPressed: onVerify,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Verify'),
                      ),
                  ],
                ),
              ],
              if (opportunity.resultNotes?.isNotEmpty ?? false)
                Consumer(
                  builder: (context, ref, _) {
                    final bool isAdmin =
                        ref.watch(isPlatformAdminProvider).value ?? false;
                    if (!(isRequester || isClaimer || isAdmin)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.cream,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Result notes', style: text.labelSmall),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              opportunity.resultNotes!,
                              style: text.bodyMedium,
                            ),
                            if (opportunity.resultUrl?.isNotEmpty ??
                                false) ...<Widget>[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                opportunity.resultUrl!,
                                style: text.bodySmall?.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _showActions {
    if (opportunity.isOpen && opportunity.requesterId != currentUserId) {
      return true;
    }
    if (opportunity.claimerId == currentUserId && !opportunity.isVerified) {
      return true;
    }
    if (opportunity.isCompanyApproved &&
        opportunity.requesterId == currentUserId &&
        opportunity.claimerId != currentUserId) {
      return true;
    }
    return false;
  }
}

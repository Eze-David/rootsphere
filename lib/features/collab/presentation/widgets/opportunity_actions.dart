import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/finder_submission.dart';
import '../../domain/entities/indexer_submission.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/role_verification.dart';
import '../providers/donation_providers.dart';
import '../providers/opportunity_providers.dart';
import '../providers/role_verification_providers.dart';
import '../screens/claim_workspace_screen.dart';
import 'donate_dialog.dart';
import 'opportunity_card.dart';
import 'role_verification_sheet.dart';

/// The signed-in user's id, or '' when signed out — matches how every
/// opportunity screen decides whether the viewer is the requester/claimer.
String currentOpportunityUserId() =>
    Supabase.instance.client.auth.currentUser?.id ?? '';

/// Opens the Finder/Indexer submission workspace for an opportunity the
/// current user has claimed. Used both right after claiming and to resume —
/// [ClaimWorkspaceScreen] always loads the opportunity's current
/// finder/indexer submission, so leaving and coming back picks up saved
/// progress rather than starting over.
void openClaimWorkspace(
  BuildContext context,
  CollaborationOpportunity opportunity,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ClaimWorkspaceScreen(opportunityId: opportunity.id),
    ),
  );
}

/// Opens the full-detail bottom sheet for an opportunity, with the
/// claim/submit/verify/unclaim actions wired up. Shared by the board, the
/// map view, and "My opportunities" so they don't each reimplement it.
Future<void> showOpportunityDetail(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  final String uid = currentOpportunityUserId();
  final bool isRequester = opportunity.requesterId == uid;
  final bool isClaimer = opportunity.claimerId == uid;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  StatusChip(
                    status: opportunity.status,
                    changesRequested: opportunity.changesRequested,
                  ),
                  if (opportunity.forCompany) const CompanyRequestBadge(),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                opportunity.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (opportunity.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  opportunity.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  if (opportunity.location?.isNotEmpty ?? false)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          opportunity.location!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        opportunity.requiredRole.icon,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        opportunity.requiredRole.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Requested by ${opportunity.requesterName}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (opportunity.claimerId != null &&
                  !opportunity.isVerified) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Attended to by ${opportunity.claimerName ?? 'someone'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (opportunity.status == OpportunityStatus.claimed &&
                  (opportunity.companyFeedback ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.sunGoldLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.feedback_outlined,
                            size: 16,
                            color: AppColors.sunGold,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Changes requested by the company',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(opportunity.companyFeedback!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Consumer(
                builder: (context, ref, _) {
                  final int raisedCents = ref.watch(
                    opportunityRaisedCentsProvider(opportunity.id),
                  );
                  if (raisedCents == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.favorite,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '₦${(raisedCents / 100).toStringAsFixed(2)} raised to support this research',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    showDonateDialog(context, ref, opportunity);
                  },
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: const Text('Support this research'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          opportunity.requiredRole.icon,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${opportunity.requiredRole.label} responsibilities',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(opportunity.requiredRole.description),
                  ],
                ),
              ),
              // Result notes and the structured Finder/Indexer submission are
              // only for the people they actually concern — the requester,
              // whoever did the work, and the company reviewing it — not
              // anyone else browsing the public board.
              Consumer(
                builder: (context, ref, _) {
                  final bool isAdmin =
                      ref.watch(isPlatformAdminProvider).value ?? false;
                  if (!(isRequester || isClaimer || isAdmin)) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (opportunity.resultNotes?.isNotEmpty ??
                          false) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        Container(
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
                              Text(
                                'Result notes',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(opportunity.resultNotes!),
                              if (opportunity.resultUrl?.isNotEmpty ??
                                  false) ...<Widget>[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  opportunity.resultUrl!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.primary),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      ..._submissionSection(context, opportunity),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (opportunity.isOpen && !isRequester)
                _ClaimSection(opportunity: opportunity, sheetContext: ctx),
              if (isClaimer && !opportunity.isVerified) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      openClaimWorkspace(context, opportunity);
                    },
                    child: const Text('Continue work'),
                  ),
                ),
                if (opportunity.isClaimed) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        submitOpportunityResult(context, ref, opportunity);
                      },
                      child: const Text('Submit result'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unclaimOpportunity(context, ref, opportunity);
                      },
                      child: const Text('Unclaim'),
                    ),
                  ),
                ] else if (opportunity.isSubmitted) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _InfoBanner(
                    icon: Icons.hourglass_top,
                    text: 'Your submission is awaiting company review.',
                  ),
                ] else if (opportunity.isCompanyApproved) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _InfoBanner(
                    icon: Icons.check_circle_outline,
                    text:
                        'Approved by the company — waiting on the '
                        "requester's final verification.",
                  ),
                ],
              ],
              if (opportunity.isSubmitted &&
                  isRequester &&
                  !isClaimer) ...<Widget>[
                _InfoBanner(
                  icon: Icons.hourglass_top,
                  text:
                      'Submitted — awaiting company review before you can '
                      'verify.',
                ),
              ],
              if (opportunity.isSubmitted)
                Consumer(
                  // Named to avoid shadowing the outer `context`/`ref` —
                  // those must be the ones used once the sheet is popped
                  // below, since this Consumer (and its own context/ref)
                  // gets disposed as part of that pop, and using a stale
                  // one silently fails the mutation with no visible error.
                  builder: (consumerContext, consumerRef, _) {
                    final bool isAdmin =
                        consumerRef.watch(isPlatformAdminProvider).value ??
                        false;
                    if (!isAdmin) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              approveSubmission(context, ref, opportunity);
                            },
                            child: const Text('Approve & forward to requester'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              rejectSubmission(context, ref, opportunity);
                            },
                            child: const Text('Request changes'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (opportunity.isCompanyApproved &&
                  isRequester &&
                  !isClaimer) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      verifyOpportunityResult(context, ref, opportunity);
                    },
                    child: const Text('Verify result'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

Future<void> claimOpportunity(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  try {
    await ref
        .read(opportunityControllerProvider.notifier)
        .claim(opportunity.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Opportunity claimed.')));
      openClaimWorkspace(context, opportunity);
    }
  } catch (e) {
    if (context.mounted) {
      // The database is the actual source of truth on qualification (the
      // pre-check below is just UX) — surface its rejection in plain
      // language instead of the raw Postgres error text.
      final String message = e.toString().contains('not_qualified_for_role')
          ? "You're not verified for this role yet."
          : e.toString().contains('company_request_admin_only')
          ? 'Only the company can claim this request.'
          : 'Could not claim: ${e.toString()}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

Future<void> submitOpportunityResult(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  final notesController = TextEditingController(
    text: opportunity.resultNotes ?? '',
  );
  final urlController = TextEditingController(
    text: opportunity.resultUrl ?? '',
  );
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Submit result'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Notes / description of what you found',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: urlController,
            decoration: const InputDecoration(
              hintText: 'Link to record or image (optional)',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await ref
                  .read(opportunityControllerProvider.notifier)
                  .submitResult(
                    opportunity.id,
                    notes: notesController.text.trim(),
                    url: urlController.text.trim().isEmpty
                        ? null
                        : urlController.text.trim(),
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Result submitted.')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not submit: ${e.toString()}')),
                );
              }
            }
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}

Future<void> verifyOpportunityResult(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Verify result'),
      content: const Text(
        'Mark this opportunity as verified? The claimer will receive credit.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Verify'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref
        .read(opportunityControllerProvider.notifier)
        .verify(opportunity.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Opportunity verified.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify: ${e.toString()}')),
      );
    }
  }
}

Future<void> approveSubmission(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  try {
    await ref
        .read(opportunityControllerProvider.notifier)
        .companyApprove(opportunity.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Approved and forwarded to requester.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not approve: ${e.toString()}')),
      );
    }
  }
}

Future<void> rejectSubmission(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  final feedbackController = TextEditingController();
  final String? feedback = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Request changes'),
      content: TextField(
        controller: feedbackController,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: "What does the claimer need to fix?",
          alignLabelWithHint: true,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final String text = feedbackController.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(ctx, text);
          },
          child: const Text('Send back'),
        ),
      ],
    ),
  );
  if (feedback == null || feedback.isEmpty) return;
  try {
    await ref
        .read(opportunityControllerProvider.notifier)
        .companyReject(opportunity.id, feedback);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent back to the claimer.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send back: ${e.toString()}')),
      );
    }
  }
}

Future<void> unclaimOpportunity(
  BuildContext context,
  WidgetRef ref,
  CollaborationOpportunity opportunity,
) async {
  try {
    await ref
        .read(opportunityControllerProvider.notifier)
        .unclaim(opportunity.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Opportunity unclaimed.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unclaim: ${e.toString()}')),
      );
    }
  }
}

/// The claimer's full structured work (Finder research or Indexer
/// transcription), so a requester (or the company, reviewing before
/// approving) sees everything — including fields the claimer left blank,
/// which matters just as much as what they did fill in when deciding
/// whether to approve. Shown once there's actually a claimer to have
/// submitted anything, not gated on whether they've filled anything in yet.
List<Widget> _submissionSection(
  BuildContext context,
  CollaborationOpportunity opportunity,
) {
  if (opportunity.claimerId == null) return const <Widget>[];
  final bool isFinder = opportunity.requiredRole == CollaborationRole.finder;

  final TextTheme text = Theme.of(context).textTheme;
  return <Widget>[
    const SizedBox(height: AppSpacing.lg),
    Text(
      isFinder ? 'Finder submission' : 'Indexer submission',
      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: AppSpacing.sm),
    if (isFinder)
      _FinderSubmissionView(
        submission: opportunity.finderSubmission ?? const FinderSubmission(),
      )
    else
      _IndexerSubmissionView(
        submission: opportunity.indexerSubmission ?? const IndexerSubmission(),
      ),
  ];
}

class _FinderSubmissionView extends StatelessWidget {
  const _FinderSubmissionView({required this.submission});
  final FinderSubmission submission;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SubmissionField(
            label: 'Confidence',
            value: submission.confidenceLevel,
          ),
          _SubmissionField(label: 'Summary', value: submission.summary),
          _SubmissionField(
            label: 'Evidence notes',
            value: submission.evidenceNotes,
          ),
          _SubmissionField(label: 'DNA notes', value: submission.dnaNotes),
          _SubmissionField(
            label: 'Compiled report / chart',
            value: submission.report,
          ),
          Text(
            'Sources (${submission.sources.length})',
            style: text.labelSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (submission.sources.isEmpty)
            Text(
              'None added',
              style: text.bodyMedium?.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            for (final ResearchSource s in submission.sources)
              _SourceTile(source: s),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});
  final ResearchSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SubmissionField(label: 'Source title', value: source.title),
          _SubmissionField(
            label: 'URL or archive reference',
            value: source.url,
          ),
          _SubmissionField(label: 'Record date', value: source.date),
          _SubmissionField(label: 'Notes', value: source.notes),
        ],
      ),
    );
  }
}

class _IndexerSubmissionView extends StatelessWidget {
  const _IndexerSubmissionView({required this.submission});
  final IndexerSubmission submission;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SubmissionField(
            label: 'Transcription',
            value: submission.transcription,
          ),
          _SubmissionField(label: 'Keywords', value: submission.keywords),
          _SubmissionField(label: 'Notes', value: submission.notes),
          _SubmissionField(
            label: 'Original image',
            value: submission.originalImageUrl,
          ),
          Text('Quality checks', style: text.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final QualityCheck q in QualityCheck.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    submission.qualityChecks.contains(q)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: submission.qualityChecks.contains(q)
                        ? AppColors.success
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(q.label, style: text.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A neutral status note shown in place of an action button when there's
/// nothing for the current viewer to do yet — e.g. "awaiting company
/// review."
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Always renders, even when [value] is empty — so a reviewer deciding
/// whether to approve sees every field the claimer *could* have filled in,
/// not just the ones they happened to. An empty field is worth knowing
/// about, not silently hidden.
class _SubmissionField extends StatelessWidget {
  const _SubmissionField({required this.label, this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = (value ?? '').trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            isEmpty ? 'Not provided' : value!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isEmpty ? AppColors.textTertiary : null,
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Replaces the plain "Claim this opportunity" button: not every opportunity
/// needs a specialist, but the ones that specify a required role only let a
/// company-approved user claim them — this shows the right thing for
/// whatever the signed-in user's application status is. Platform admins
/// skip all of that and can always claim directly, same trust level as
/// approving/rejecting submissions.
class _ClaimSection extends ConsumerWidget {
  const _ClaimSection({required this.opportunity, required this.sheetContext});

  final CollaborationOpportunity opportunity;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;
    if (isAdmin) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () {
            Navigator.pop(sheetContext);
            claimOpportunity(context, ref, opportunity);
          },
          child: Text(
            opportunity.forCompany
                ? 'Claim this request'
                : 'Claim this opportunity',
          ),
        ),
      );
    }

    if (opportunity.forCompany) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.apartment_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This request was sent directly to the company.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final RoleVerification? verification = ref.watch(
      myVerificationForRoleProvider(opportunity.requiredRole),
    );

    if (verification?.status == VerificationStatus.approved) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () {
            Navigator.pop(sheetContext);
            claimOpportunity(context, ref, opportunity);
          },
          child: const Text('Claim this opportunity'),
        ),
      );
    }

    if (verification?.status == VerificationStatus.pending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.hourglass_top,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Your ${opportunity.requiredRole.label} application is '
                'awaiting review.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    // No application yet, or a previous one was rejected — same call to
    // action either way (the sheet lets them reapply).
    final bool rejected = verification?.status == VerificationStatus.rejected;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          Navigator.pop(sheetContext);
          showRoleVerificationSheet(context, opportunity.requiredRole);
        },
        child: Text(
          rejected
              ? 'Reapply as ${opportunity.requiredRole.label}'
              : 'Apply to become a ${opportunity.requiredRole.label}',
        ),
      ),
    );
  }
}

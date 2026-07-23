import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/opportunity_providers.dart';
import '../widgets/opportunity_actions.dart';
import '../widgets/opportunity_card.dart';

/// The company's queue of Finder/Indexer submissions awaiting review, before
/// they're forwarded to the requester for final verification. Approve/reject
/// (with feedback) live inside the opportunity's own detail sheet — see
/// showOpportunityDetail — so this screen is just the browsing list.
class SubmissionReviewScreen extends ConsumerStatefulWidget {
  const SubmissionReviewScreen({super.key, this.openOpportunityId});

  /// When set (arriving from a notification tap), the matching submission's
  /// detail sheet opens automatically once it loads.
  final String? openOpportunityId;

  @override
  ConsumerState<SubmissionReviewScreen> createState() =>
      _SubmissionReviewScreenState();
}

class _SubmissionReviewScreenState
    extends ConsumerState<SubmissionReviewScreen> {
  String? _pendingOpenId;

  @override
  void initState() {
    super.initState();
    _pendingOpenId = widget.openOpportunityId;
  }

  void _maybeAutoOpen(List<CollaborationOpportunity> submissions) {
    final String? id = _pendingOpenId;
    if (id == null) return;
    final CollaborationOpportunity? match = submissions
        .cast<CollaborationOpportunity?>()
        .firstWhere((o) => o?.id == id, orElse: () => null);
    if (match == null) return;
    _pendingOpenId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showOpportunityDetail(context, ref, match);
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String uid = currentOpportunityUserId();
    final List<CollaborationOpportunity> submissions = ref.watch(
      pendingSubmissionsProvider,
    );
    _maybeAutoOpen(submissions);

    return Scaffold(
      appBar: AppBar(title: const Text('Review submissions')),
      body: submissions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.fact_check_outlined,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Nothing to review', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "Work a Finder or Indexer submits shows up here before "
                      "it's forwarded to the requester.",
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: submissions.length,
              itemBuilder: (_, index) {
                final CollaborationOpportunity opportunity = submissions[index];
                return OpportunityCard(
                  opportunity: opportunity,
                  currentUserId: uid,
                  onTap: () => showOpportunityDetail(context, ref, opportunity),
                );
              },
            ),
    );
  }
}

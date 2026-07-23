import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/opportunity_providers.dart';
import '../widgets/opportunity_actions.dart';
import '../widgets/opportunity_card.dart';

/// The company's private queue of opportunities sent directly to it rather
/// than posted to the public board. RLS already restricts
/// [companyOpportunitiesProvider]'s underlying stream to the requester and
/// platform admins, so nobody else can ever land here with data to see.
class CompanyRequestsScreen extends ConsumerStatefulWidget {
  const CompanyRequestsScreen({super.key, this.openOpportunityId});

  /// When set (arriving from a notification tap), the matching request's
  /// detail sheet opens automatically once it loads.
  final String? openOpportunityId;

  @override
  ConsumerState<CompanyRequestsScreen> createState() =>
      _CompanyRequestsScreenState();
}

class _CompanyRequestsScreenState extends ConsumerState<CompanyRequestsScreen> {
  String? _pendingOpenId;

  @override
  void initState() {
    super.initState();
    _pendingOpenId = widget.openOpportunityId;
  }

  void _maybeAutoOpen(List<CollaborationOpportunity> requests) {
    final String? id = _pendingOpenId;
    if (id == null) return;
    final CollaborationOpportunity? match = requests
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
    final List<CollaborationOpportunity> requests = ref.watch(
      companyOpportunitiesProvider,
    );
    _maybeAutoOpen(requests);

    return Scaffold(
      appBar: AppBar(title: const Text('Company requests')),
      body: requests.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.apartment_outlined,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('No requests yet', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Requests sent directly to the company (skipping the '
                      'public board) show up here.',
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
              itemCount: requests.length,
              itemBuilder: (_, index) {
                final CollaborationOpportunity opportunity = requests[index];
                return OpportunityCard(
                  opportunity: opportunity,
                  currentUserId: uid,
                  onTap: () => showOpportunityDetail(context, ref, opportunity),
                  onClaim: () => claimOpportunity(context, ref, opportunity),
                  onContinueWork: () =>
                      openClaimWorkspace(context, opportunity),
                  onSubmitResult: () =>
                      submitOpportunityResult(context, ref, opportunity),
                  onVerify: () =>
                      verifyOpportunityResult(context, ref, opportunity),
                  onUnclaim: () =>
                      unclaimOpportunity(context, ref, opportunity),
                );
              },
            ),
    );
  }
}

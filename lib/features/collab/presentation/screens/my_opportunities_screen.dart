import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/opportunity_providers.dart';
import '../widgets/opportunity_actions.dart';
import '../widgets/opportunity_card.dart';

/// A person's own view of the collaboration board: opportunities they've
/// claimed (work they've done or are doing) on one tab, and opportunities
/// they've posted for the community (what they've requested) on the other.
class MyOpportunitiesScreen extends ConsumerWidget {
  const MyOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String uid = currentOpportunityUserId();
    final List<CollaborationOpportunity> claimed = ref.watch(
      myClaimedOpportunitiesProvider,
    );
    final List<CollaborationOpportunity> requested = ref.watch(
      myRequestedOpportunitiesProvider,
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My opportunities'),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: 'Claimed (${claimed.length})'),
              Tab(text: 'Requested (${requested.length})'),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: _ContributionHeader(),
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _OpportunityList(
                    opportunities: claimed,
                    currentUserId: uid,
                    emptyIcon: Icons.volunteer_activism_outlined,
                    emptyTitle: 'Nothing claimed yet',
                    emptySubtitle:
                        "Opportunities you claim from the board show up here so "
                        "you can track what you've taken on.",
                  ),
                  _OpportunityList(
                    opportunities: requested,
                    currentUserId: uid,
                    emptyIcon: Icons.campaign_outlined,
                    emptyTitle: 'Nothing requested yet',
                    emptySubtitle:
                        'Opportunities you post for the community to help with '
                        'show up here.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContributionHeader extends ConsumerWidget {
  const _ContributionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final my = ref.watch(myContributionProvider);
    if (my == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Your contributions', style: text.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${my.verifiedCount} verified · ${my.claimedCount} claimed',
                  style: text.bodyMedium,
                ),
                Text('${my.reputation} reputation', style: text.bodySmall),
              ],
            ),
          ),
          if (my.badges.isNotEmpty)
            Row(
              children: my.badges.take(3).map((badge) {
                return Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Tooltip(
                    message: '${badge.label}: ${badge.description}',
                    child: Icon(
                      badge.icon,
                      color: Theme.of(context).colorScheme.primary,
                      size: 22,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _OpportunityList extends StatelessWidget {
  const _OpportunityList({
    required this.opportunities,
    required this.currentUserId,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<CollaborationOpportunity> opportunities;
  final String currentUserId;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (opportunities.isEmpty) {
      final TextTheme text = Theme.of(context).textTheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(emptyIcon, size: 48, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(emptyTitle, style: text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: opportunities.length,
          itemBuilder: (_, index) {
            final CollaborationOpportunity opportunity = opportunities[index];
            return OpportunityCard(
              opportunity: opportunity,
              currentUserId: currentUserId,
              onTap: () => showOpportunityDetail(context, ref, opportunity),
              onClaim: () => claimOpportunity(context, ref, opportunity),
              onContinueWork: () => openClaimWorkspace(context, opportunity),
              onSubmitResult: () =>
                  submitOpportunityResult(context, ref, opportunity),
              onVerify: () =>
                  verifyOpportunityResult(context, ref, opportunity),
              onUnclaim: () => unclaimOpportunity(context, ref, opportunity),
            );
          },
        );
      },
    );
  }
}

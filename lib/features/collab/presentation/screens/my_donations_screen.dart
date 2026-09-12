import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/donation.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/donation_providers.dart';
import '../providers/opportunity_providers.dart';
import '../../../../shared/widgets/error_retry_view.dart';
import '../widgets/donate_dialog.dart';
import '../widgets/opportunity_card.dart';

/// A person's own donation history — every one-time payment they've made
/// supporting other people's research, across every opportunity.
class MyDonationsScreen extends ConsumerWidget {
  const MyDonationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Donation>> async = ref.watch(myDonationsProvider);
    final List<DonationSubscription> subscriptions =
        ref.watch(mySubscriptionsProvider).value ??
        const <DonationSubscription>[];
    final List<CollaborationOpportunity> opportunities =
        ref.watch(opportunitiesProvider).value ??
        const <CollaborationOpportunity>[];
    final Map<String, String> titleById = <String, String>{
      for (final o in opportunities) o.id: o.title,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('My donations'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Make a donation',
            icon: const Icon(Icons.add),
            onPressed: opportunities.isEmpty
                ? null
                : () => _pickOpportunityToDonate(context, ref, opportunities),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (subscriptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: _RecurringSection(subscriptions: subscriptions),
            ),
          Expanded(
            child: _buildOneTimeSection(
              context,
              ref,
              async,
              opportunities,
              titleById,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOneTimeSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Donation>> async,
    List<CollaborationOpportunity> opportunities,
    Map<String, String> titleById,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetryView(
        error: e,
        onRetry: () => ref.invalidate(myDonationsProvider),
      ),
      data: (donations) {
        if (donations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.volunteer_activism_outlined,
                    size: 48,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('No donations yet', style: text.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'When you support a research opportunity, it shows up here.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (opportunities.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () =>
                          _pickOpportunityToDonate(context, ref, opportunities),
                      icon: const Icon(Icons.favorite_border, size: 18),
                      label: const Text('Make a donation'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        final int totalGivenCents = donations
            .where((d) => d.status == DonationStatus.completed)
            .fold<int>(0, (sum, d) => sum + d.amountCents);

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            if (totalGivenCents > 0) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Total given', style: text.labelSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      // Donations are only ever made in NGN today (see
                      // donate_dialog.dart) — safe to sum raw cents.
                      '₦${(totalGivenCents / 100).toStringAsFixed(2)}',
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            for (final Donation d in donations)
              _DonationTile(
                donation: d,
                opportunityTitle: titleById[d.opportunityId],
              ),
          ],
        );
      },
    );
  }
}

class _DonationTile extends StatelessWidget {
  const _DonationTile({required this.donation, required this.opportunityTitle});
  final Donation donation;
  final String? opportunityTitle;

  Color get _statusColor {
    switch (donation.status) {
      case DonationStatus.completed:
        return AppColors.success;
      case DonationStatus.pending:
        return AppColors.sunGold;
      case DonationStatus.failed:
        return AppColors.error;
      case DonationStatus.refunded:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    opportunityTitle ?? 'Opportunity',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  donation.formattedAmount,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  ),
                  child: Text(
                    donation.status.label,
                    style: text.labelSmall?.copyWith(
                      color: _statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (donation.createdAt != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _formatDate(donation.createdAt!),
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
            if ((donation.message ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                donation.message!,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// Lets the donor choose which opportunity to support, since every donation
/// is tied to a specific research request rather than the app in general.
Future<void> _pickOpportunityToDonate(
  BuildContext context,
  WidgetRef ref,
  List<CollaborationOpportunity> opportunities,
) async {
  final CollaborationOpportunity?
  chosen = await showModalBottomSheet<CollaborationOpportunity>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (ctx) {
      final TextTheme text = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'Choose what to support',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: opportunities.length,
                itemBuilder: (_, index) {
                  final CollaborationOpportunity o = opportunities[index];
                  return ListTile(
                    title: Text(o.title),
                    subtitle: Text(
                      'By ${o.requesterName}'
                      '${(o.location?.isNotEmpty ?? false) ? ' · ${o.location}' : ''}',
                    ),
                    trailing: StatusChip(
                      status: o.status,
                      changesRequested: o.changesRequested,
                    ),
                    onTap: () => Navigator.pop(ctx, o),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      );
    },
  );
  if (chosen != null && context.mounted) {
    await showDonateDialog(context, ref, chosen);
  }
}

/// Monthly/Annual recurring donations — shown above the one-time history so
/// a donor can see and cancel an active subscription at a glance. Web/
/// Android only (see 20260910000000_donation_subscriptions.sql).
class _RecurringSection extends StatelessWidget {
  const _RecurringSection({required this.subscriptions});
  final List<DonationSubscription> subscriptions;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('RECURRING', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        for (final DonationSubscription s in subscriptions)
          _SubscriptionTile(subscription: s),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
      ],
    );
  }
}

class _SubscriptionTile extends ConsumerStatefulWidget {
  const _SubscriptionTile({required this.subscription});
  final DonationSubscription subscription;

  @override
  ConsumerState<_SubscriptionTile> createState() => _SubscriptionTileState();
}

class _SubscriptionTileState extends ConsumerState<_SubscriptionTile> {
  bool _cancelling = false;

  Color _statusColor(DonationSubscriptionStatus status) {
    switch (status) {
      case DonationSubscriptionStatus.active:
        return AppColors.success;
      case DonationSubscriptionStatus.pending:
        return AppColors.sunGold;
      case DonationSubscriptionStatus.cancelled:
        return AppColors.textSecondary;
      case DonationSubscriptionStatus.failed:
        return AppColors.error;
    }
  }

  Future<void> _confirmCancel() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel recurring donation?'),
        content: Text(
          'This stops future ${widget.subscription.interval.label.toLowerCase()} '
          'charges. Past contributions aren\'t affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep giving'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    final result = await ref
        .read(donationCheckoutServiceProvider)
        .cancelSubscription(widget.subscription.id);
    if (!mounted) return;
    setState(() => _cancelling = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Your recurring donation has been cancelled.'
              : (result.message ?? 'Could not cancel this donation.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DonationSubscription s = widget.subscription;
    final bool canCancel =
        s.status == DonationSubscriptionStatus.active ||
        s.status == DonationSubscriptionStatus.pending;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    s.purpose?.label ?? 'General RootSphere Programs',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${s.formattedAmount} · ${s.interval.label}',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: _statusColor(s.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              ),
              child: Text(
                s.status.label,
                style: text.labelSmall?.copyWith(
                  color: _statusColor(s.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (canCancel) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _cancelling ? null : _confirmCancel,
                  child: _cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cancel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

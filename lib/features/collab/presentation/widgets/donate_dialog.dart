import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/donation_providers.dart';

// In kobo (NGN's smallest unit): ₦500, ₦1,000, ₦2,500, ₦5,000, ₦10,000.
const List<int> _presetAmountsCents = <int>[
  50000,
  100000,
  250000,
  500000,
  1000000,
];

/// Shows the "Support this research" flow: pick an amount, enter an email
/// (Paystack requires one) and optionally a name/message, then opens the
/// Paystack payment page in the browser. The donation is only ever marked
/// complete by the `paystack-webhook` function — this just starts it.
///
/// When [opportunity] is omitted, this is a general donation to Rootsphere
/// itself rather than a specific research opportunity — e.g. from the
/// sign-in screen, for someone who doesn't want to create an account just
/// to donate.
Future<void> showDonateDialog(
  BuildContext context,
  WidgetRef ref, [
  CollaborationOpportunity? opportunity,
]) async {
  int? selectedCents = _presetAmountsCents[1];
  final TextEditingController customController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  bool submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        int? amountCents() {
          if (selectedCents != null) return selectedCents;
          final double? custom = double.tryParse(customController.text.trim());
          if (custom == null || custom <= 0) return null;
          return (custom * 100).round();
        }

        Future<void> submit() async {
          final int? cents = amountCents();
          if (cents == null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Enter an amount to donate.')),
            );
            return;
          }
          final String email = emailController.text.trim();
          if (!email.contains('@') || !email.contains('.')) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Enter a valid email address.')),
            );
            return;
          }
          setState(() => submitting = true);
          final result = await ref
              .read(donationCheckoutServiceProvider)
              .createCheckout(
                opportunityId: opportunity?.id,
                opportunityTitle: opportunity?.title,
                treeId: opportunity?.treeId,
                amountCents: cents,
                donorEmail: email,
                donorName: nameController.text.trim().isEmpty
                    ? null
                    : nameController.text.trim(),
                message: messageController.text.trim().isEmpty
                    ? null
                    : messageController.text.trim(),
              );
          if (!ctx.mounted) return;
          setState(() => submitting = false);
          if (!result.available || result.paymentUrl == null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(result.message ?? 'Could not start checkout.'),
              ),
            );
            return;
          }
          Navigator.pop(ctx);
          await launchUrl(
            Uri.parse(result.paymentUrl!),
            mode: LaunchMode.externalApplication,
          );
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.lg,
              bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  opportunity == null
                      ? 'Support Rootsphere'
                      : 'Support this research',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  opportunity?.title ??
                      'Help us build and maintain the platform.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final cents in _presetAmountsCents)
                      ChoiceChip(
                        label: Text('₦${(cents / 100).toStringAsFixed(0)}'),
                        selected: selectedCents == cents,
                        onSelected: (_) => setState(() {
                          selectedCents = cents;
                          customController.clear();
                        }),
                      ),
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: selectedCents == null,
                      onSelected: (_) => setState(() => selectedCents = null),
                    ),
                  ],
                ),
                if (selectedCents == null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: customController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '₦ ',
                      hintText: 'Amount',
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Email (for your receipt)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Your name (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: messageController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Message (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: submitting ? null : submit,
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Continue to payment'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Handled securely by Paystack. You\'ll finish payment in your browser.',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/apple_iap_donation_service.dart';
import '../../domain/entities/donation.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/donation_providers.dart';

/// Shows the donate flow appropriate to the platform: Apple In-App Purchase
/// natively on iOS (required by App Store Guideline 3.1.1 — a donation
/// button counts as a paid transaction there regardless of it being
/// optional), or the existing Paystack checkout everywhere else.
///
/// When [opportunity] is omitted, this is a general donation to Rootsphere
/// itself rather than a specific research opportunity — e.g. from the
/// sign-in screen, for someone who doesn't want to create an account just
/// to donate.
Future<void> showDonateDialog(
  BuildContext context,
  WidgetRef ref, [
  CollaborationOpportunity? opportunity,
]) {
  if (!kIsWeb && Platform.isIOS) {
    return _showAppleIapDonateSheet(context, ref, opportunity);
  }
  return _showPaystackDonateSheet(context, ref, opportunity);
}

/// Pick an amount, enter an email (Paystack requires one) and optionally a
/// name/message, then opens the Paystack payment page in the browser. The
/// donation is only ever marked complete by the `paystack-webhook` function
/// — this just starts it.
Future<void> _showPaystackDonateSheet(
  BuildContext context,
  WidgetRef ref, [
  CollaborationOpportunity? opportunity,
]) async {
  int? selectedCents = presetDonationAmounts[1].cents;
  DonationPurpose purpose = DonationPurpose.whereMostNeeded;
  bool anonymous = false;
  final TextEditingController customController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  bool submitting = false;
  final bool signedIn = Supabase.instance.client.auth.currentUser != null;

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
                donorName: anonymous || nameController.text.trim().isEmpty
                    ? null
                    : nameController.text.trim(),
                message: messageController.text.trim().isEmpty
                    ? null
                    : messageController.text.trim(),
                purpose: purpose,
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
          // On web, opening a new tab/window this long after the user's tap
          // (an await for the network round-trip has happened in between)
          // no longer counts as a "direct" user gesture to the browser, so
          // popup blockers silently swallow LaunchMode.externalApplication
          // here — same-tab navigation is never blocked, and Paystack's
          // callback_url already brings the user right back into the app.
          await launchUrl(
            Uri.parse(result.paymentUrl!),
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: kIsWeb ? '_self' : null,
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
            child: SingleChildScrollView(
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
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    signedIn
                        ? 'This will be saved to your donation history.'
                        : 'No account needed — you\'re donating as a guest, '
                              'and a receipt will be sent to your email.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      for (final tier in presetDonationAmounts)
                        ChoiceChip(
                          label: Text(
                            '₦${(tier.cents / 100).toStringAsFixed(0)} · ${tier.name}',
                          ),
                          selected: selectedCents == tier.cents,
                          onSelected: (_) => setState(() {
                            selectedCents = tier.cents;
                            customController.clear();
                          }),
                        ),
                      ChoiceChip(
                        label: const Text('Other Amount'),
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
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'I would like my contribution to support:',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<DonationPurpose>(
                    initialValue: purpose,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: <DropdownMenuItem<DonationPurpose>>[
                      for (final p in DonationPurpose.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (p) {
                      if (p != null) setState(() => purpose = p);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Email (for your receipt)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (!anonymous)
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Your name (optional)',
                      ),
                    ),
                  CheckboxListTile(
                    value: anonymous,
                    onChanged: (v) => setState(() => anonymous = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Make my contribution anonymous'),
                  ),
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
          ),
        );
      },
    ),
  );
}

/// Pick one of the fixed consumable tiers and pay via Apple's native
/// in-app-purchase sheet — no email/custom amount, Apple handles the
/// payment and receipt entirely. Only recorded as a completed donation once
/// `apple-iap-verify` confirms it against Apple's own transaction record.
Future<void> _showAppleIapDonateSheet(
  BuildContext context,
  WidgetRef ref, [
  CollaborationOpportunity? opportunity,
]) async {
  final AppleIapDonationService service = ref.read(
    appleIapDonationServiceProvider,
  );

  if (!await service.isAvailable()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('In-app purchases aren\'t available right now.'),
      ),
    );
    return;
  }

  final Map<String, ProductDetails> tiers = await service.queryTiers();
  if (!context.mounted) return;
  if (tiers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Donation options aren\'t available right now.'),
      ),
    );
    return;
  }

  final List<ProductDetails> orderedTiers = <ProductDetails>[
    for (final String id in appleDonationTierProductIds)
      if (tiers[id] != null) tiers[id]!,
  ];
  ProductDetails selected = orderedTiers.first;
  DonationPurpose purpose = DonationPurpose.whereMostNeeded;
  bool anonymous = false;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  bool submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submit() async {
          setState(() => submitting = true);
          final AppleIapDonationResult result = await service.donate(
            product: selected,
            opportunityId: opportunity?.id,
            treeId: opportunity?.treeId,
            donorName: anonymous || nameController.text.trim().isEmpty
                ? null
                : nameController.text.trim(),
            message: messageController.text.trim().isEmpty
                ? null
                : messageController.text.trim(),
            purpose: purpose,
          );
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          if (!context.mounted) return;
          final String snackText = switch (result) {
            AppleIapDonationResult(success: true) =>
              'Thank You! Your contribution has been received. Every gift '
                  'helps RootSphere preserve family history for generations '
                  'to come.',
            AppleIapDonationResult(canceled: true) =>
              'Payment Cancelled. Your contribution was not completed and '
                  'no donation has been recorded.',
            _ =>
              result.message ??
                  'Your Contribution Was Not Completed. Please try again or '
                      'choose another payment method.',
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(snackText)));
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.lg,
              bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
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
                      for (final ProductDetails tier in orderedTiers)
                        ChoiceChip(
                          label: Text(tier.price),
                          selected: selected.id == tier.id,
                          onSelected: (_) => setState(() => selected = tier),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'I would like my contribution to support:',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<DonationPurpose>(
                    initialValue: purpose,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: <DropdownMenuItem<DonationPurpose>>[
                      for (final p in DonationPurpose.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (p) {
                      if (p != null) setState(() => purpose = p);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (!anonymous)
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Your name (optional)',
                      ),
                    ),
                  CheckboxListTile(
                    value: anonymous,
                    onChanged: (v) => setState(() => anonymous = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Make my contribution anonymous'),
                  ),
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
                          : Text('Donate ${selected.price}'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Processed securely by Apple.',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

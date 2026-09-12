import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/donation.dart';
import '../providers/donation_providers.dart';

/// Final step before the actual Paystack charge — "You're Helping Preserve
/// Something Priceless": review what was picked on [DonationDetailsScreen],
/// provide an email for the receipt, and hand off to Paystack's hosted
/// checkout (which itself offers card, bank transfer, USSD, and whatever
/// else your Paystack account has enabled — no need to duplicate that
/// picker here).
class DonationReviewScreen extends ConsumerStatefulWidget {
  const DonationReviewScreen({
    super.key,
    required this.amountCents,
    required this.purpose,
    this.donorName,
    this.message,
    this.interval,
  });

  final int amountCents;
  final DonationPurpose purpose;
  final String? donorName;
  final String? message;

  /// Null means a one-time donation; otherwise this becomes a recurring
  /// Paystack subscription instead of a single charge.
  final DonationInterval? interval;

  @override
  ConsumerState<DonationReviewScreen> createState() =>
      _DonationReviewScreenState();
}

class _DonationReviewScreenState extends ConsumerState<DonationReviewScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final String email = _emailController.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final DonationInterval? interval = widget.interval;
    final result = interval == null
        ? await ref
              .read(donationCheckoutServiceProvider)
              .createCheckout(
                amountCents: widget.amountCents,
                donorEmail: email,
                donorName: widget.donorName,
                message: widget.message,
                purpose: widget.purpose,
              )
        : await ref
              .read(donationCheckoutServiceProvider)
              .createSubscriptionCheckout(
                amountCents: widget.amountCents,
                donorEmail: email,
                interval: interval,
                donorName: widget.donorName,
                message: widget.message,
                purpose: widget.purpose,
              );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.available || result.paymentUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Could not start checkout.')),
      );
      return;
    }
    // Same-tab navigation, not a new window: this happens after an `await`
    // (the network round-trip above), so it's no longer a "direct" user
    // gesture as far as the browser's popup blocker is concerned — opening a
    // new tab here gets silently swallowed. Paystack's callback_url brings
    // the user right back into the app once they finish anyway.
    await launchUrl(
      Uri.parse(result.paymentUrl!),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Donation preview = Donation(id: '', amountCents: widget.amountCents);
    final DonationInterval? interval = widget.interval;
    final String amountLine = interval == null
        ? 'Amount: ${preview.formattedAmount}'
        : 'Amount: ${preview.formattedAmount} (${interval.label.toLowerCase()})';

    return Scaffold(
      appBar: AppBar(
        title: Text(interval == null ? 'Review Contribution' : 'Review Giving'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    interval == null
                        ? 'You\'re Helping Preserve Something Priceless'
                        : 'Become a RootSphere Heritage Partner',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    interval == null
                        ? 'You are one step away from helping preserve '
                              'family stories and historical records for '
                              'future generations. Please review your '
                              'contribution and select your preferred '
                              'payment method.'
                        : 'A recurring contribution provides continued '
                              'support for family history research, record '
                              'preservation, education, and community '
                              'heritage projects. You can cancel anytime '
                              'from Profile ▸ Donations.',
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(amountLine, style: text.bodyMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Purpose: ${widget.purpose.label}',
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'From: ${widget.donorName ?? 'Anonymous'}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Email (for your receipt)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _complete,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              interval == null
                                  ? 'Complete Contribution'
                                  : 'Give ${interval.label}',
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Handled securely by Paystack. You\'ll finish payment in '
                    'your browser.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

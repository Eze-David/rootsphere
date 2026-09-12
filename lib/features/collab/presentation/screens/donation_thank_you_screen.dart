import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/donation_checkout_service.dart';
import '../../domain/entities/donation.dart';
import '../providers/donation_providers.dart';

/// Where Paystack redirects the browser after checkout (`callback_url`) —
/// a real page on our own domain rather than a Supabase Edge Function URL
/// (see [AppRoutes.donationThankYou]). Paystack's redirect itself doesn't
/// say whether the payment succeeded; this page polls `donation-status`
/// (via [reference]) for the real outcome, which `paystack-webhook`
/// confirms asynchronously and usually within a couple of seconds.
class DonationThankYouScreen extends ConsumerStatefulWidget {
  const DonationThankYouScreen({super.key, this.reference});

  final String? reference;

  @override
  ConsumerState<DonationThankYouScreen> createState() =>
      _DonationThankYouScreenState();
}

enum _Phase { processing, succeeded, failed, unknown }

class _DonationThankYouScreenState
    extends ConsumerState<DonationThankYouScreen> {
  _Phase _phase = _Phase.processing;
  DonationStatusResult? _result;
  Timer? _pollTimer;
  int _attempts = 0;

  static const int _maxAttempts = 8;
  static const Duration _pollInterval = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    if (widget.reference == null) {
      _phase = _Phase.unknown;
    } else {
      _poll();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    _attempts++;
    final DonationStatusResult result = await ref
        .read(donationCheckoutServiceProvider)
        .checkStatus(widget.reference!);
    if (!mounted) return;

    if (result.found && result.status == DonationStatus.completed) {
      setState(() {
        _result = result;
        _phase = _Phase.succeeded;
      });
      return;
    }
    if (result.found && result.status == DonationStatus.failed) {
      setState(() {
        _result = result;
        _phase = _Phase.failed;
      });
      return;
    }
    if (_attempts >= _maxAttempts) {
      // The webhook is just slow, not necessarily failed — don't tell
      // someone their payment failed when it might still land any second.
      setState(() => _phase = _Phase.unknown);
      return;
    }
    _pollTimer = Timer(_pollInterval, _poll);
  }

  Future<void> _copyShareMessage(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(
        text:
            'I just supported RootSphere Family History Foundation — help '
            'preserve family histories, memories, and heritage for future '
            'generations: https://www.rootsphere.ink',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied! Share it with someone.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (_phase) {
                _Phase.processing => _Processing(text: text),
                _Phase.succeeded => _Succeeded(
                  text: text,
                  reference: widget.reference,
                  result: _result,
                  onCopyShare: () => _copyShareMessage(context),
                ),
                _Phase.failed => const _Failed(),
                _Phase.unknown => const _StillProcessing(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({required this.text});
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Processing Your Contribution…',
          style: text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Please wait while we securely confirm your payment. Do not '
          'close this page until the transaction is completed.',
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Succeeded extends StatelessWidget {
  const _Succeeded({
    required this.text,
    required this.reference,
    required this.result,
    required this.onCopyShare,
  });

  final TextTheme text;
  final String? reference;
  final DonationStatusResult? result;
  final VoidCallback onCopyShare;

  void _showReceipt(BuildContext context) {
    final DonationStatusResult? r = result;
    final String amount = (r?.amountCents != null && r?.currency != null)
        ? Donation(
            id: '',
            amountCents: r!.amountCents!,
            currency: r.currency!,
          ).formattedAmount
        : '—';
    final String date = r?.createdAt != null
        ? '${r!.createdAt!.day}/${r.createdAt!.month}/${r.createdAt!.year}'
        : '—';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thank You for Your Contribution'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'This receipt confirms your contribution to RootSphere '
              'Family History & Genealogy Foundation. Please keep it for '
              'your records.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Contribution Reference: ${reference ?? '—'}'),
            const SizedBox(height: AppSpacing.xs),
            Text('Date: $date'),
            const SizedBox(height: AppSpacing.xs),
            Text('Amount: $amount'),
            const SizedBox(height: AppSpacing.xs),
            Text('Purpose: ${r?.purpose?.label ?? 'Where Most Needed'}'),
            const SizedBox(height: AppSpacing.xs),
            const Text('Payment Status: Successful'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.favorite,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Thank You for Helping Preserve a Legacy!',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your contribution has been received successfully. Because of '
          'people like you, more family stories, memories, photographs, '
          'records, and histories can be preserved and passed from one '
          'generation to another.\n\nRootSphere appreciates your support. '
          'Together, we are connecting generations and preserving legacies.',
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _showReceipt(context),
            child: const Text('View Receipt'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Return Home'),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Inspire Someone Else to Preserve a Legacy',
          style: text.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'You can make an even greater impact by inviting your family and '
          'friends to join us in preserving family histories.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: onCopyShare,
          child: const Text('Share RootSphere'),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed();

  static const String _supportEmail = 'contact.us@rootsphere.ink';

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.error_outline,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Your Contribution Was Not Completed',
          style: text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We could not confirm your payment. You have not been charged '
          'if the transaction was unsuccessful. Please try again or choose '
          'another available payment method.\n\nIf your account was '
          'debited but the payment is showing as unsuccessful, please '
          'contact RootSphere Support.',
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Try Again'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => launchUrl(Uri.parse('mailto:$_supportEmail')),
            child: const Text('Contact Support'),
          ),
        ),
      ],
    );
  }
}

/// The webhook hasn't confirmed either way yet by the time we stopped
/// polling — not necessarily a failure, so this stays reassuring rather
/// than alarming (matches the old, single-message behavior this replaces).
class _StillProcessing extends StatelessWidget {
  const _StillProcessing();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.favorite,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Thank you!',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          "Thanks for supporting RootSphere. If your payment went "
          "through, it'll be confirmed and show up shortly.",
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('Return to Rootsphere'),
        ),
      ],
    );
  }
}

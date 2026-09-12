import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/apple_iap_donation_service.dart';
import '../../domain/entities/donation.dart';
import '../providers/donation_providers.dart';
import 'donation_review_screen.dart';

/// Second step of the donation wizard — "Choose How You Would Like to Make
/// a Difference": pick a Donation Type (One-Time / Monthly / Annually) and
/// an amount, then what it supports. On iOS, "amount" means one of Apple's
/// fixed IAP products instead of an arbitrary figure — required by App
/// Store Guideline 3.1.1 for one-time tiers, and Apple only offers
/// auto-renewable subscriptions as fixed-price products by design for
/// recurring.
///
/// On iOS this screen completes the donation itself (Apple's own purchase
/// sheet is the payment step — inserting a separate custom review page in
/// between would just be a redundant second confirmation). Everywhere else,
/// "Continue" moves on to [DonationReviewScreen], which is where the actual
/// Paystack charge (one-time or recurring) happens.
class DonationDetailsScreen extends ConsumerStatefulWidget {
  const DonationDetailsScreen({super.key});

  @override
  ConsumerState<DonationDetailsScreen> createState() =>
      _DonationDetailsScreenState();
}

class _DonationDetailsScreenState extends ConsumerState<DonationDetailsScreen> {
  int? _selectedCents = presetDonationAmounts[1].cents;
  DonationPurpose _purpose = DonationPurpose.whereMostNeeded;
  DonationInterval? _interval; // null = one-time
  bool _anonymous = false;
  final TextEditingController _customController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  // Apple IAP state — only ever populated/used when _isIOS.
  bool _loadingTiers = true;
  List<ProductDetails> _appleTiers = <ProductDetails>[];
  ProductDetails? _selectedAppleTier;
  Map<String, ProductDetails> _appleSubscriptionTiers =
      <String, ProductDetails>{};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (_isIOS) _loadAppleProducts();
  }

  @override
  void dispose() {
    _customController.dispose();
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadAppleProducts() async {
    final AppleIapDonationService service = ref.read(
      appleIapDonationServiceProvider,
    );
    if (!await service.isAvailable()) {
      if (mounted) setState(() => _loadingTiers = false);
      return;
    }
    final Map<String, ProductDetails> tiers = await service.queryTiers();
    final Map<String, ProductDetails> subscriptionTiers = await service
        .querySubscriptionTiers();
    if (!mounted) return;
    final List<ProductDetails> ordered = <ProductDetails>[
      for (final String id in appleDonationTierProductIds)
        if (tiers[id] != null) tiers[id]!,
    ];
    setState(() {
      _appleTiers = ordered;
      _selectedAppleTier = ordered.isNotEmpty ? ordered.first : null;
      _appleSubscriptionTiers = subscriptionTiers;
      _loadingTiers = false;
    });
  }

  ProductDetails? get _selectedAppleSubscriptionTier {
    final DonationInterval? i = _interval;
    if (i == null) return null;
    final String id = i == DonationInterval.monthly
        ? appleMonthlySubscriptionProductId
        : appleAnnualSubscriptionProductId;
    return _appleSubscriptionTiers[id];
  }

  int? _amountCents() {
    if (_selectedCents != null) return _selectedCents;
    final double? custom = double.tryParse(_customController.text.trim());
    if (custom == null || custom <= 0) return null;
    return (custom * 100).round();
  }

  String? get _donorName => _anonymous || _nameController.text.trim().isEmpty
      ? null
      : _nameController.text.trim();

  String? get _message => _messageController.text.trim().isEmpty
      ? null
      : _messageController.text.trim();

  Future<void> _continueApple() async {
    final ProductDetails? tier = _selectedAppleTier;
    if (tier == null) return;
    setState(() => _submitting = true);
    final AppleIapDonationResult result = await ref
        .read(appleIapDonationServiceProvider)
        .donate(
          product: tier,
          donorName: _donorName,
          message: _message,
          purpose: _purpose,
        );
    _finishApple(result);
  }

  Future<void> _subscribeApple() async {
    final ProductDetails? tier = _selectedAppleSubscriptionTier;
    if (tier == null) return;
    setState(() => _submitting = true);
    final AppleIapDonationResult result = await ref
        .read(appleIapDonationServiceProvider)
        .subscribe(
          product: tier,
          donorName: _donorName,
          message: _message,
          purpose: _purpose,
        );
    _finishApple(result);
  }

  void _finishApple(AppleIapDonationResult result) {
    if (!mounted) return;
    setState(() => _submitting = false);
    final String snackText = switch (result) {
      AppleIapDonationResult(success: true) =>
        'Thank You! Your contribution has been received. Every gift helps '
            'RootSphere preserve family history for generations to come.',
      AppleIapDonationResult(canceled: true) =>
        'Payment Cancelled. Your contribution was not completed and no '
            'donation has been recorded.',
      _ =>
        result.message ??
            'Your Contribution Was Not Completed. Please try again or '
                'choose another payment method.',
    };
    if (result.success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(snackText)));
  }

  void _continuePaystack() {
    final int? cents = _amountCents();
    if (cents == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount to donate.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DonationReviewScreen(
          amountCents: cents,
          purpose: _purpose,
          donorName: _donorName,
          message: _message,
          interval: _interval,
        ),
      ),
    );
  }

  VoidCallback? get _onSubmit {
    if (_submitting) return null;
    if (!_isIOS) return _continuePaystack;
    return _interval == null ? _continueApple : _subscribeApple;
  }

  String get _submitLabel {
    if (!_isIOS) return 'Continue';
    return _interval == null ? 'Donate' : 'Subscribe';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool signedIn = Supabase.instance.client.auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Make a Difference')),
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
                    'Choose How You Would Like to Make a Difference',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your contribution can support family history research, '
                    'record preservation, oral history projects, community '
                    'outreach, genealogy education, and the continued '
                    'development of RootSphere.',
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Donation Type', style: text.bodyMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('One-Time'),
                        selected: _interval == null,
                        onSelected: (_) => setState(() => _interval = null),
                      ),
                      for (final DonationInterval i in DonationInterval.values)
                        ChoiceChip(
                          label: Text(i.label),
                          selected: _interval == i,
                          onSelected: (_) => setState(() => _interval = i),
                        ),
                    ],
                  ),
                  if (_interval != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Become a RootSphere Heritage Partner — even a small '
                      '${_interval!.label.toLowerCase()} contribution can '
                      'help preserve stories that might otherwise be lost.',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (_isIOS) ...<Widget>[
                    if (_loadingTiers)
                      const Center(child: CircularProgressIndicator())
                    else if (_interval == null)
                      if (_appleTiers.isEmpty)
                        const Text(
                          'Donation options aren\'t available right now.',
                        )
                      else
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: <Widget>[
                            for (final ProductDetails tier in _appleTiers)
                              ChoiceChip(
                                label: Text(tier.price),
                                selected: _selectedAppleTier?.id == tier.id,
                                onSelected: (_) =>
                                    setState(() => _selectedAppleTier = tier),
                              ),
                          ],
                        )
                    else if (_selectedAppleSubscriptionTier == null)
                      const Text(
                        'This subscription option isn\'t available right '
                        'now.',
                      )
                    else
                      Text(
                        '${_selectedAppleSubscriptionTier!.price} / '
                        '${_interval!.label.toLowerCase()}',
                        style: text.titleMedium,
                      ),
                  ] else ...<Widget>[
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final tier in presetDonationAmounts)
                          ChoiceChip(
                            label: Text(
                              '₦${(tier.cents / 100).toStringAsFixed(0)} · ${tier.name}',
                            ),
                            selected: _selectedCents == tier.cents,
                            onSelected: (_) => setState(() {
                              _selectedCents = tier.cents;
                              _customController.clear();
                            }),
                          ),
                        ChoiceChip(
                          label: const Text('Other Amount'),
                          selected: _selectedCents == null,
                          onSelected: (_) =>
                              setState(() => _selectedCents = null),
                        ),
                      ],
                    ),
                    if (_selectedCents == null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _customController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          prefixText: '₦ ',
                          hintText: 'Amount',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'I would like my contribution to support:',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<DonationPurpose>(
                    initialValue: _purpose,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: <DropdownMenuItem<DonationPurpose>>[
                      for (final p in DonationPurpose.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (p) {
                      if (p != null) setState(() => _purpose = p);
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (!_anonymous)
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Your name (optional)',
                      ),
                    ),
                  CheckboxListTile(
                    value: _anonymous,
                    onChanged: (v) => setState(() => _anonymous = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Make my contribution anonymous'),
                  ),
                  TextField(
                    controller: _messageController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Message (optional)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    signedIn
                        ? 'This will be saved to your donation history.'
                        : 'No account needed — a receipt will be sent to '
                              'your email.',
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _onSubmit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_submitLabel),
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

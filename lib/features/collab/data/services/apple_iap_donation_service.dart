import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/donation.dart';

/// The fixed consumable donation tiers — Apple IAP requires a fixed price
/// per product (no arbitrary custom amount like the Paystack flow allows).
/// These Product IDs must exist, as Consumable in-app purchases, in App
/// Store Connect exactly as written here.
const List<String> appleDonationTierProductIds = <String>[
  'com.rootsphere.rootsphere.donation.tier1',
  'com.rootsphere.rootsphere.donation.tier2',
  'com.rootsphere.rootsphere.donation.tier3',
  'com.rootsphere.rootsphere.donation.tier4',
  'com.rootsphere.rootsphere.donation.tier5',
];

/// The 2 Auto-Renewable Subscription products ("RootSphere Heritage
/// Partner" group) — Monthly and Annual recurring giving on iOS. Distinct
/// products from the consumable tiers above; each needs its own App Store
/// Connect setup and review.
const String appleMonthlySubscriptionProductId =
    'com.rootsphere.rootsphere.donation.monthly';
const String appleAnnualSubscriptionProductId =
    'com.rootsphere.rootsphere.donation.annual';
const List<String> appleSubscriptionProductIds = <String>[
  appleMonthlySubscriptionProductId,
  appleAnnualSubscriptionProductId,
];

class AppleIapDonationResult {
  const AppleIapDonationResult({
    required this.success,
    this.message,
    this.canceled = false,
  });
  final bool success;
  final String? message;

  /// True when the donor themselves dismissed Apple's purchase sheet — a
  /// distinct, unalarming case from a real payment failure, so the UI can
  /// show "Payment Cancelled" instead of an error message.
  final bool canceled;
}

/// Runs an iOS donation entirely through Apple's In-App Purchase system —
/// required by App Store Guideline 3.1.1, which treats a donation button as
/// a paid-content transaction subject to IAP regardless of it being
/// optional. Android and the web keep the Paystack flow in
/// [DonationCheckoutService] unchanged.
///
/// A purchase is only ever recorded as a completed donation by the
/// `apple-iap-verify` Edge Function, which asks Apple's own App Store Server
/// API for the authoritative transaction/amount — this class never writes
/// to the `donations` table directly, matching how the Paystack flow can
/// only be confirmed by `paystack-webhook`.
class AppleIapDonationService {
  AppleIapDonationService() : _iap = InAppPurchase.instance;

  final InAppPurchase _iap;

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Looks up the App Store Connect-configured price/title for each tier —
  /// keyed by product ID, missing entries mean that product isn't approved/
  /// available yet.
  Future<Map<String, ProductDetails>> queryTiers() async {
    final ProductDetailsResponse response = await _iap.queryProductDetails(
      appleDonationTierProductIds.toSet(),
    );
    return <String, ProductDetails>{
      for (final ProductDetails p in response.productDetails) p.id: p,
    };
  }

  /// Looks up the App Store Connect-configured price/title for each
  /// subscription product — keyed by product ID.
  Future<Map<String, ProductDetails>> querySubscriptionTiers() async {
    final ProductDetailsResponse response = await _iap.queryProductDetails(
      appleSubscriptionProductIds.toSet(),
    );
    return <String, ProductDetails>{
      for (final ProductDetails p in response.productDetails) p.id: p,
    };
  }

  /// Starts a Monthly/Annual recurring donation via Apple's native
  /// auto-renewable subscription purchase sheet. Every renewal after this
  /// first one is recorded by the `apple-subscription-poll` cron job, not
  /// by the client — Apple doesn't tell the app directly when a background
  /// renewal happens.
  Future<AppleIapDonationResult> subscribe({
    required ProductDetails product,
    String? donorName,
    String? message,
    DonationPurpose? purpose,
  }) async {
    final Completer<AppleIapDonationResult> completer =
        Completer<AppleIapDonationResult>();
    late final StreamSubscription<List<PurchaseDetails>> subscription;

    subscription = _iap.purchaseStream.listen((purchases) async {
      for (final PurchaseDetails purchase in purchases) {
        if (purchase.productID != product.id) continue;
        switch (purchase.status) {
          case PurchaseStatus.pending:
            continue;
          case PurchaseStatus.error:
            if (!completer.isCompleted) {
              completer.complete(
                AppleIapDonationResult(
                  success: false,
                  message: purchase.error?.message ?? 'Purchase failed.',
                ),
              );
            }
          case PurchaseStatus.canceled:
            if (!completer.isCompleted) {
              completer.complete(
                const AppleIapDonationResult(success: false, canceled: true),
              );
            }
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            final AppleIapDonationResult result = await _verifySubscription(
              purchase: purchase,
              donorName: donorName,
              message: message,
              purpose: purpose,
            );
            if (!completer.isCompleted) completer.complete(result);
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    });

    try {
      final bool started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        return const AppleIapDonationResult(
          success: false,
          message: 'Could not start the purchase.',
        );
      }
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => const AppleIapDonationResult(
          success: false,
          message: 'The purchase timed out — please try again.',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<AppleIapDonationResult> _verifySubscription({
    required PurchaseDetails purchase,
    String? donorName,
    String? message,
    DonationPurpose? purpose,
  }) async {
    if (!SupabaseConfig.isReady) {
      return const AppleIapDonationResult(
        success: false,
        message: 'Donations aren\'t set up yet.',
      );
    }
    try {
      final String? uid = SupabaseConfig.client.auth.currentUser?.id;
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'apple-subscription-verify',
        body: <String, dynamic>{
          'transactionId': purchase.purchaseID,
          'productId': purchase.productID,
          'donorId': uid,
          'donorName': donorName,
          'message': message,
          'purpose': purpose?.name,
        },
      );
      final dynamic data = res.data;
      final bool ok =
          res.status == 200 && data is Map && data['available'] == true;
      if (ok) return const AppleIapDonationResult(success: true);
      final String failureMessage =
          (data is Map ? data['message']?.toString() : null) ??
          'Could not confirm your donation.';
      return AppleIapDonationResult(success: false, message: failureMessage);
    } on FunctionException catch (e) {
      return AppleIapDonationResult(
        success: false,
        message: 'Could not confirm your donation (${e.status}).',
      );
    } catch (_) {
      return const AppleIapDonationResult(
        success: false,
        message: 'Could not confirm your donation.',
      );
    }
  }

  /// Buys [product] as a consumable, waits for StoreKit to resolve it,
  /// verifies the purchase server-side, and only resolves once the donation
  /// is either confirmed recorded or definitively failed/canceled.
  Future<AppleIapDonationResult> donate({
    required ProductDetails product,
    String? opportunityId,
    String? treeId,
    String? donorName,
    String? message,
    DonationPurpose? purpose,
  }) async {
    final Completer<AppleIapDonationResult> completer =
        Completer<AppleIapDonationResult>();
    late final StreamSubscription<List<PurchaseDetails>> subscription;

    subscription = _iap.purchaseStream.listen((purchases) async {
      for (final PurchaseDetails purchase in purchases) {
        if (purchase.productID != product.id) continue;
        switch (purchase.status) {
          case PurchaseStatus.pending:
            continue;
          case PurchaseStatus.error:
            if (!completer.isCompleted) {
              completer.complete(
                AppleIapDonationResult(
                  success: false,
                  message: purchase.error?.message ?? 'Purchase failed.',
                ),
              );
            }
          case PurchaseStatus.canceled:
            if (!completer.isCompleted) {
              completer.complete(
                const AppleIapDonationResult(success: false, canceled: true),
              );
            }
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            final AppleIapDonationResult result = await _verify(
              purchase: purchase,
              opportunityId: opportunityId,
              treeId: treeId,
              donorName: donorName,
              message: message,
              purpose: purpose,
            );
            if (!completer.isCompleted) completer.complete(result);
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    });

    try {
      final bool started = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        return const AppleIapDonationResult(
          success: false,
          message: 'Could not start the purchase.',
        );
      }
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => const AppleIapDonationResult(
          success: false,
          message: 'The purchase timed out — please try again.',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<AppleIapDonationResult> _verify({
    required PurchaseDetails purchase,
    String? opportunityId,
    String? treeId,
    String? donorName,
    String? message,
    DonationPurpose? purpose,
  }) async {
    if (!SupabaseConfig.isReady) {
      return const AppleIapDonationResult(
        success: false,
        message: 'Donations aren\'t set up yet.',
      );
    }
    try {
      final String? uid = SupabaseConfig.client.auth.currentUser?.id;
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'apple-iap-verify',
        body: <String, dynamic>{
          'transactionId': purchase.purchaseID,
          'productId': purchase.productID,
          'opportunityId': opportunityId,
          'treeId': treeId,
          'donorId': uid,
          'donorName': donorName,
          'message': message,
          'purpose': purpose?.name,
        },
      );
      final dynamic data = res.data;
      final bool ok =
          res.status == 200 && data is Map && data['available'] == true;
      if (ok) return const AppleIapDonationResult(success: true);
      final String failureMessage =
          (data is Map ? data['message']?.toString() : null) ??
          'Could not confirm your donation.';
      return AppleIapDonationResult(success: false, message: failureMessage);
    } on FunctionException catch (e) {
      return AppleIapDonationResult(
        success: false,
        message: 'Could not confirm your donation (${e.status}).',
      );
    } catch (_) {
      return const AppleIapDonationResult(
        success: false,
        message: 'Could not confirm your donation.',
      );
    }
  }
}

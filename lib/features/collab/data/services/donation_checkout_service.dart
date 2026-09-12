import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/donation.dart';

/// Outcome of starting a donation payment.
class DonationCheckoutResult {
  const DonationCheckoutResult({
    required this.available,
    this.paymentUrl,
    this.message,
  });

  final bool available;

  /// The Paystack payment page URL to open (in an external browser) when
  /// [available] is true.
  final String? paymentUrl;
  final String? message;
}

/// The real outcome of a donation, looked up by reference — what
/// [DonationCheckoutResult] can't tell you, since Paystack's checkout
/// redirect doesn't distinguish success from failure itself.
class DonationStatusResult {
  const DonationStatusResult({
    required this.found,
    this.status,
    this.amountCents,
    this.currency,
    this.purpose,
    this.donorName,
    this.createdAt,
  });

  final bool found;
  final DonationStatus? status;
  final int? amountCents;
  final String? currency;
  final DonationPurpose? purpose;
  final String? donorName;
  final DateTime? createdAt;
}

/// Outcome of cancelling a recurring donation.
class CancelSubscriptionResult {
  const CancelSubscriptionResult({required this.success, this.message});
  final bool success;
  final String? message;
}

/// Starts a one-time Paystack transaction for supporting a specific
/// opportunity's research, via the `create-donation-transaction` Edge
/// Function (keeps the Paystack secret key server-side, same "keys never on
/// client" pattern as the AI/OCR/geocoding functions). Degrades gracefully —
/// returns `available: false` rather than throwing — whenever
/// Supabase/Paystack aren't configured or the request fails.
class DonationCheckoutService {
  DonationCheckoutService();

  /// [opportunityId]/[opportunityTitle]/[treeId] are omitted for a general
  /// donation to Rootsphere itself, not tied to any specific research
  /// opportunity — either all three are provided, or none are.
  Future<DonationCheckoutResult> createCheckout({
    String? opportunityId,
    String? opportunityTitle,
    String? treeId,
    required int amountCents,
    required String donorEmail,
    String currency = 'ngn',
    String? donorName,
    String? message,
    DonationPurpose? purpose,
  }) async {
    if (!SupabaseConfig.isReady) {
      return const DonationCheckoutResult(
        available: false,
        message:
            'Donations aren\'t set up yet — connect Supabase to enable them.',
      );
    }
    try {
      final String? uid = SupabaseConfig.client.auth.currentUser?.id;
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'create-donation-transaction',
        body: <String, dynamic>{
          'opportunityId': opportunityId,
          'opportunityTitle': opportunityTitle,
          'treeId': treeId,
          'amountCents': amountCents,
          'currency': currency,
          'donorName': donorName,
          'donorEmail': donorEmail,
          'message': message,
          'donorId': uid,
          'purpose': purpose?.name,
        },
      );
      if (res.status != 200) {
        return DonationCheckoutResult(
          available: false,
          message: 'Donation service returned ${res.status}.',
        );
      }
      final dynamic data = res.data;
      if (data is! Map) {
        return const DonationCheckoutResult(
          available: false,
          message: 'Unexpected response from the donation service.',
        );
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(data);
      if (map['available'] != true) {
        return DonationCheckoutResult(
          available: false,
          message: map['message']?.toString(),
        );
      }
      return DonationCheckoutResult(
        available: true,
        paymentUrl: map['authorizationUrl']?.toString(),
      );
    } on FunctionException catch (e) {
      return DonationCheckoutResult(
        available: false,
        message: 'Donations unavailable (${e.status}).',
      );
    } catch (_) {
      return const DonationCheckoutResult(
        available: false,
        message: 'Could not reach the donation service.',
      );
    }
  }

  /// Looks up a donation's real status by its reference — used by
  /// [DonationThankYouScreen] to show an actual success/failure state
  /// instead of one message regardless of outcome. Works for guest donors
  /// too: `donation-status` trusts the reference itself (an unguessable
  /// string only the donor's browser has seen) rather than a session.
  Future<DonationStatusResult> checkStatus(String reference) async {
    if (!SupabaseConfig.isReady) {
      return const DonationStatusResult(found: false);
    }
    try {
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'donation-status',
        method: HttpMethod.get,
        queryParameters: <String, String>{'reference': reference},
      );
      final dynamic data = res.data;
      if (res.status != 200 || data is! Map || data['found'] != true) {
        return const DonationStatusResult(found: false);
      }
      DonationStatus? status;
      for (final DonationStatus s in DonationStatus.values) {
        if (s.name == data['status']) status = s;
      }
      DonationPurpose? purpose;
      for (final DonationPurpose p in DonationPurpose.values) {
        if (p.name == data['purpose']) purpose = p;
      }
      return DonationStatusResult(
        found: true,
        status: status,
        amountCents: (data['amountCents'] as num?)?.round(),
        currency: data['currency'] as String?,
        purpose: purpose,
        donorName: data['donorName'] as String?,
        createdAt: data['createdAt'] == null
            ? null
            : DateTime.tryParse(data['createdAt'].toString()),
      );
    } catch (_) {
      return const DonationStatusResult(found: false);
    }
  }

  /// Starts a Monthly/Annual recurring donation, via the
  /// `create-donation-subscription` Edge Function (Paystack Plans +
  /// Subscriptions) — web/Android only, see [DonationInterval].
  Future<DonationCheckoutResult> createSubscriptionCheckout({
    required int amountCents,
    required String donorEmail,
    required DonationInterval interval,
    String currency = 'ngn',
    String? donorName,
    String? message,
    DonationPurpose? purpose,
  }) async {
    if (!SupabaseConfig.isReady) {
      return const DonationCheckoutResult(
        available: false,
        message:
            'Donations aren\'t set up yet — connect Supabase to enable them.',
      );
    }
    try {
      final String? uid = SupabaseConfig.client.auth.currentUser?.id;
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'create-donation-subscription',
        body: <String, dynamic>{
          'amountCents': amountCents,
          'currency': currency,
          'interval': interval.name,
          'donorName': donorName,
          'donorEmail': donorEmail,
          'message': message,
          'donorId': uid,
          'purpose': purpose?.name,
        },
      );
      if (res.status != 200) {
        return DonationCheckoutResult(
          available: false,
          message: 'Donation service returned ${res.status}.',
        );
      }
      final dynamic data = res.data;
      if (data is! Map) {
        return const DonationCheckoutResult(
          available: false,
          message: 'Unexpected response from the donation service.',
        );
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(data);
      if (map['available'] != true) {
        return DonationCheckoutResult(
          available: false,
          message: map['message']?.toString(),
        );
      }
      return DonationCheckoutResult(
        available: true,
        paymentUrl: map['authorizationUrl']?.toString(),
      );
    } on FunctionException catch (e) {
      return DonationCheckoutResult(
        available: false,
        message: 'Donations unavailable (${e.status}).',
      );
    } catch (_) {
      return const DonationCheckoutResult(
        available: false,
        message: 'Could not reach the donation service.',
      );
    }
  }

  /// Cancels a recurring donation via `cancel-donation-subscription` —
  /// requires sign-in, and only works for the donor who owns it (guest-made
  /// recurring donations have no account to authorize this against, and
  /// must be cancelled by emailing support instead).
  Future<CancelSubscriptionResult> cancelSubscription(
    String subscriptionId,
  ) async {
    if (!SupabaseConfig.isReady) {
      return const CancelSubscriptionResult(
        success: false,
        message: 'Donations aren\'t set up yet.',
      );
    }
    try {
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'cancel-donation-subscription',
        body: <String, dynamic>{'subscriptionId': subscriptionId},
      );
      final dynamic data = res.data;
      final bool ok =
          res.status == 200 && data is Map && data['success'] == true;
      if (ok) return const CancelSubscriptionResult(success: true);
      return CancelSubscriptionResult(
        success: false,
        message:
            (data is Map ? data['message']?.toString() : null) ??
            'Could not cancel this subscription.',
      );
    } on FunctionException catch (e) {
      return CancelSubscriptionResult(
        success: false,
        message: 'Could not cancel (${e.status}).',
      );
    } catch (_) {
      return const CancelSubscriptionResult(
        success: false,
        message: 'Could not cancel this subscription.',
      );
    }
  }
}

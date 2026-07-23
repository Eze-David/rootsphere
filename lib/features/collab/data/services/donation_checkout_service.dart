import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

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

/// Starts a one-time Paystack transaction for supporting a specific
/// opportunity's research, via the `create-donation-transaction` Edge
/// Function (keeps the Paystack secret key server-side, same "keys never on
/// client" pattern as the AI/OCR/geocoding functions). Degrades gracefully —
/// returns `available: false` rather than throwing — whenever
/// Supabase/Paystack aren't configured or the request fails.
class DonationCheckoutService {
  DonationCheckoutService();

  Future<DonationCheckoutResult> createCheckout({
    required String opportunityId,
    required String opportunityTitle,
    required String treeId,
    required int amountCents,
    required String donorEmail,
    String currency = 'ngn',
    String? donorName,
    String? message,
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
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../data/repositories/donation_repository_local.dart';
import '../../data/repositories/donation_repository_supabase.dart';
import '../../data/services/donation_checkout_service.dart';
import '../../domain/entities/donation.dart';
import '../../domain/repositories/donation_repository.dart';

/// Donation repository: Supabase-backed (read-only) when configured, a no-op
/// stub otherwise — real donations require the live Paystack/Edge Function
/// backend.
final donationRepositoryProvider = Provider<DonationRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return DonationRepositorySupabase(SupabaseConfig.client);
  }
  return DonationRepositoryLocal();
});

/// Starts a Paystack transaction for a donation (Supabase Edge Function).
final donationCheckoutServiceProvider = Provider<DonationCheckoutService>(
  (ref) => DonationCheckoutService(),
);

/// Donations for a given opportunity, newest first.
final opportunityDonationsProvider =
    StreamProvider.family<List<Donation>, String>((ref, opportunityId) {
      return ref
          .watch(donationRepositoryProvider)
          .watchDonations(opportunityId);
    });

/// Every donation the signed-in user has made, across all opportunities,
/// newest first — powers the "My donations" screen from the Profile tab.
final myDonationsProvider = StreamProvider<List<Donation>>((ref) {
  final String? uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return Stream<List<Donation>>.value(const <Donation>[]);
  return ref
      .watch(donationRepositoryProvider)
      .watchMyDonations(uid)
      .map(
        (donations) => donations.toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          ),
      );
});

/// Total raised (in cents) for a given opportunity — only counts completed
/// donations, so pending/failed checkout attempts don't inflate the total.
final opportunityRaisedCentsProvider = Provider.family<int, String>((
  ref,
  opportunityId,
) {
  final List<Donation> donations =
      ref.watch(opportunityDonationsProvider(opportunityId)).value ??
      const <Donation>[];
  return donations
      .where((d) => d.status == DonationStatus.completed)
      .fold<int>(0, (sum, d) => sum + d.amountCents);
});

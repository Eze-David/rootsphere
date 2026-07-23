import '../entities/donation.dart';

/// Read-only access to donations — rows are only ever written by the
/// `create-donation-transaction` / `paystack-webhook` Edge Functions, never
/// by the client directly (see the `donations` table's RLS policy).
abstract class DonationRepository {
  /// Streams donations for a given opportunity, newest first.
  Stream<List<Donation>> watchDonations(String opportunityId);

  /// One-shot read of donations for a given opportunity.
  Future<List<Donation>> getDonations(String opportunityId);

  /// Streams every donation made by a given donor, across all opportunities,
  /// newest first — powers the "My donations" screen.
  Stream<List<Donation>> watchMyDonations(String donorId);
}

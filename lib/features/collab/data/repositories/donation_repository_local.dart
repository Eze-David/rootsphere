import '../../domain/entities/donation.dart';
import '../../domain/repositories/donation_repository.dart';

/// Used when Supabase isn't configured. Real donations require a live
/// payment backend (Paystack via the Edge Functions), so local/demo mode has
/// nothing to show — the donate action itself explains this rather than
/// silently pretending to work.
class DonationRepositoryLocal implements DonationRepository {
  @override
  Stream<List<Donation>> watchDonations(String opportunityId) =>
      Stream<List<Donation>>.value(const <Donation>[]);

  @override
  Future<List<Donation>> getDonations(String opportunityId) async =>
      const <Donation>[];

  @override
  Stream<List<Donation>> watchMyDonations(String donorId) =>
      Stream<List<Donation>>.value(const <Donation>[]);
}

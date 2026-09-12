import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/donation.dart';
import '../../domain/repositories/donation_repository.dart';

/// Supabase-backed [DonationRepository] — read-only from the client's side.
/// Donations are written only by the `create-donation-transaction` and
/// `paystack-webhook` Edge Functions (service role), matching the
/// `donations` table's RLS policy.
class DonationRepositorySupabase implements DonationRepository {
  DonationRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _donations => _client.from('donations');

  @override
  Stream<List<Donation>> watchDonations(String opportunityId) {
    return _donations
        .stream(primaryKey: <String>['id'])
        .eq('opportunity_id', opportunityId)
        .order('created_at')
        .map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Future<List<Donation>> getDonations(String opportunityId) async {
    try {
      final List<Map<String, dynamic>> rows = await _donations
          .select()
          .eq('opportunity_id', opportunityId)
          .order('created_at', ascending: false);
      return rows.map(_fromRow).toList();
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Stream<List<Donation>> watchMyDonations(String donorId) {
    return _donations
        .stream(primaryKey: <String>['id'])
        .eq('donor_id', donorId)
        .order('created_at')
        .map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Stream<List<DonationSubscription>> watchMySubscriptions(String donorId) {
    return _client
        .from('donation_subscriptions')
        .stream(primaryKey: <String>['id'])
        .eq('donor_id', donorId)
        .order('created_at')
        .map((rows) => rows.map(_subscriptionFromRow).toList());
  }

  DonationSubscription _subscriptionFromRow(Map<String, dynamic> row) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return DonationSubscription(
      id: row['id'] as String,
      donorId: row['donor_id'] as String?,
      donorName: row['donor_name'] as String? ?? 'Anonymous',
      donorEmail: row['donor_email'] as String?,
      message: row['message'] as String?,
      purpose: _purposeFromColumn(row['purpose'] as String?),
      amountCents: (row['amount_cents'] as num?)?.round() ?? 0,
      currency: row['currency'] as String? ?? 'ngn',
      interval: DonationInterval.values.firstWhere(
        (i) => i.name == row['interval'],
        orElse: () => DonationInterval.monthly,
      ),
      status: DonationSubscriptionStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => DonationSubscriptionStatus.pending,
      ),
      createdAt: parse(row['created_at']),
      cancelledAt: parse(row['cancelled_at']),
    );
  }

  Donation _fromRow(Map<String, dynamic> row) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return Donation(
      id: row['id'] as String,
      opportunityId: row['opportunity_id'] as String?,
      treeId: row['tree_id'] as String?,
      donorId: row['donor_id'] as String?,
      donorName: row['donor_name'] as String? ?? 'Anonymous',
      donorEmail: row['donor_email'] as String?,
      message: row['message'] as String?,
      purpose: _purposeFromColumn(row['purpose'] as String?),
      amountCents: (row['amount_cents'] as num?)?.round() ?? 0,
      currency: row['currency'] as String? ?? 'ngn',
      status: DonationStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => DonationStatus.pending,
      ),
      createdAt: parse(row['created_at']),
      completedAt: parse(row['completed_at']),
    );
  }
}

DonationPurpose? _purposeFromColumn(String? name) {
  if (name == null) return null;
  for (final DonationPurpose p in DonationPurpose.values) {
    if (p.name == name) return p;
  }
  return null;
}

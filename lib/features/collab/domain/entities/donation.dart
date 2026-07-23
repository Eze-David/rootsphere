/// Lifecycle of a one-time donation payment.
enum DonationStatus { pending, completed, failed, refunded }

extension DonationStatusX on DonationStatus {
  String get label {
    switch (this) {
      case DonationStatus.pending:
        return 'Processing';
      case DonationStatus.completed:
        return 'Completed';
      case DonationStatus.failed:
        return 'Failed';
      case DonationStatus.refunded:
        return 'Refunded';
    }
  }
}

/// A one-time payment supporting the research on a specific
/// [CollaborationOpportunity] — separate from the paid Finder/Indexer work
/// itself. Created via Paystack (see the `create-donation-transaction` Edge
/// Function) and only ever confirmed by the `paystack-webhook` function; the
/// client never marks a donation "completed" directly.
class Donation {
  const Donation({
    required this.id,
    required this.opportunityId,
    required this.treeId,
    this.donorId,
    this.donorName = 'Anonymous',
    this.donorEmail,
    this.message,
    required this.amountCents,
    this.currency = 'ngn',
    this.status = DonationStatus.pending,
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String opportunityId;
  final String treeId;
  final String? donorId;
  final String donorName;
  final String? donorEmail;
  final String? message;

  /// Amount in the smallest currency unit (kobo for NGN), matching
  /// Paystack's own convention — avoids floating-point rounding on money.
  final int amountCents;
  final String currency;
  final DonationStatus status;
  final DateTime? createdAt;
  final DateTime? completedAt;

  double get amount => amountCents / 100;

  /// Formatted amount, e.g. "₦5,000.00". Only handles the currencies this
  /// app actually offers in the donation picker (see the amount presets).
  String get formattedAmount {
    final String symbol = switch (currency.toLowerCase()) {
      'ngn' => '₦',
      'ghs' => 'GH₵',
      'zar' => 'R',
      'kes' => 'KSh',
      'usd' => r'$',
      _ => '${currency.toUpperCase()} ',
    };
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  factory Donation.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return Donation(
      id: json['id'] as String,
      opportunityId: json['opportunityId'] as String,
      treeId: json['treeId'] as String,
      donorId: json['donorId'] as String?,
      donorName: json['donorName'] as String? ?? 'Anonymous',
      donorEmail: json['donorEmail'] as String?,
      message: json['message'] as String?,
      amountCents: (json['amountCents'] as num?)?.round() ?? 0,
      currency: json['currency'] as String? ?? 'ngn',
      status: DonationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => DonationStatus.pending,
      ),
      createdAt: parse(json['createdAt']),
      completedAt: parse(json['completedAt']),
    );
  }
}

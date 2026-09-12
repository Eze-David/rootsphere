/// A preset donation amount paired with the honorific RootSphere gives it
/// (in kobo, NGN's smallest unit) — shared by the quick-donate sheet and the
/// full donation wizard so the two never drift apart.
class DonationAmountTier {
  const DonationAmountTier(this.cents, this.name);
  final int cents;
  final String name;
}

const List<DonationAmountTier> presetDonationAmounts = <DonationAmountTier>[
  DonationAmountTier(200000, 'Supporter'),
  DonationAmountTier(500000, 'Heritage Friend'),
  DonationAmountTier(1000000, 'Family History Supporter'),
  DonationAmountTier(2500000, 'Heritage Champion'),
  DonationAmountTier(5000000, 'Preservation Partner'),
  DonationAmountTier(10000000, 'Legacy Partner'),
];

/// What a donation is earmarked to support — purely informational (doesn't
/// change how the payment is processed), lets a donor feel the money is
/// going somewhere specific.
enum DonationPurpose {
  generalPrograms,
  familyHistoryResearch,
  oralHistory,
  recordDigitization,
  genealogyEducation,
  appDevelopment,
  aiResearchAssistant,
  whereMostNeeded,
}

extension DonationPurposeX on DonationPurpose {
  String get label {
    switch (this) {
      case DonationPurpose.generalPrograms:
        return 'General RootSphere Programs';
      case DonationPurpose.familyHistoryResearch:
        return 'Family History Research';
      case DonationPurpose.oralHistory:
        return 'Oral History & Community Documentation';
      case DonationPurpose.recordDigitization:
        return 'Record Digitization & Preservation';
      case DonationPurpose.genealogyEducation:
        return 'Genealogy Education & Training';
      case DonationPurpose.appDevelopment:
        return 'Technology & RootSphere App Development';
      case DonationPurpose.aiResearchAssistant:
        return 'AI Research Assistants';
      case DonationPurpose.whereMostNeeded:
        return 'Where Most Needed';
    }
  }
}

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
    this.opportunityId,
    this.treeId,
    this.donorId,
    this.donorName = 'Anonymous',
    this.donorEmail,
    this.message,
    this.purpose,
    required this.amountCents,
    this.currency = 'ngn',
    this.status = DonationStatus.pending,
    this.createdAt,
    this.completedAt,
  });

  final String id;

  /// Null for a general donation to Rootsphere itself, not tied to any
  /// specific research opportunity.
  final String? opportunityId;
  final String? treeId;
  final String? donorId;
  final String donorName;
  final String? donorEmail;
  final String? message;
  final DonationPurpose? purpose;

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
  String get formattedAmount => formatMoney(amountCents, currency);

  factory Donation.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return Donation(
      id: json['id'] as String,
      opportunityId: json['opportunityId'] as String?,
      treeId: json['treeId'] as String?,
      donorId: json['donorId'] as String?,
      donorName: json['donorName'] as String? ?? 'Anonymous',
      donorEmail: json['donorEmail'] as String?,
      message: json['message'] as String?,
      purpose: _purposeFromName(json['purpose'] as String?),
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

DonationPurpose? _purposeFromName(String? name) {
  if (name == null) return null;
  for (final DonationPurpose p in DonationPurpose.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// Formats an amount (smallest currency unit) with the right symbol, e.g.
/// "₦5,000.00" — shared by [Donation] and [DonationSubscription] so the two
/// never format money differently.
String formatMoney(int amountCents, String currency) {
  final String symbol = switch (currency.toLowerCase()) {
    'ngn' => '₦',
    'ghs' => 'GH₵',
    'zar' => 'R',
    'kes' => 'KSh',
    'usd' => r'$',
    _ => '${currency.toUpperCase()} ',
  };
  return '$symbol${(amountCents / 100).toStringAsFixed(2)}';
}

/// How often a recurring donation renews. One-time donations use [Donation]
/// directly and have no interval at all.
enum DonationInterval {
  monthly,
  annually;

  String get label => switch (this) {
    DonationInterval.monthly => 'Monthly',
    DonationInterval.annually => 'Annually',
  };
}

/// Lifecycle of a recurring donation (Paystack subscription) — distinct from
/// [DonationStatus] since "active" only makes sense for something ongoing.
enum DonationSubscriptionStatus {
  pending,
  active,
  cancelled,
  failed;

  String get label => switch (this) {
    DonationSubscriptionStatus.pending => 'Activating',
    DonationSubscriptionStatus.active => 'Active',
    DonationSubscriptionStatus.cancelled => 'Cancelled',
    DonationSubscriptionStatus.failed => 'Failed',
  };
}

/// A Monthly/Annual recurring donation — web/Android only, via Paystack's
/// Plans + Subscriptions API (see `create-donation-subscription`). Every
/// individual charge against it (the first payment and every renewal)
/// becomes its own [Donation] row linked back here by `subscriptionId`, so
/// giving history always reads the same way regardless of whether a
/// donation was one-time or recurring.
class DonationSubscription {
  const DonationSubscription({
    required this.id,
    this.donorId,
    this.donorName = 'Anonymous',
    this.donorEmail,
    this.message,
    this.purpose,
    required this.amountCents,
    this.currency = 'ngn',
    required this.interval,
    this.status = DonationSubscriptionStatus.pending,
    this.createdAt,
    this.cancelledAt,
  });

  final String id;
  final String? donorId;
  final String donorName;
  final String? donorEmail;
  final String? message;
  final DonationPurpose? purpose;
  final int amountCents;
  final String currency;
  final DonationInterval interval;
  final DonationSubscriptionStatus status;
  final DateTime? createdAt;
  final DateTime? cancelledAt;

  String get formattedAmount => formatMoney(amountCents, currency);

  factory DonationSubscription.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return DonationSubscription(
      id: json['id'] as String,
      donorId: json['donorId'] as String?,
      donorName: json['donorName'] as String? ?? 'Anonymous',
      donorEmail: json['donorEmail'] as String?,
      message: json['message'] as String?,
      purpose: _purposeFromName(json['purpose'] as String?),
      amountCents: (json['amountCents'] as num?)?.round() ?? 0,
      currency: json['currency'] as String? ?? 'ngn',
      interval: DonationInterval.values.firstWhere(
        (i) => i.name == json['interval'],
        orElse: () => DonationInterval.monthly,
      ),
      status: DonationSubscriptionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => DonationSubscriptionStatus.pending,
      ),
      createdAt: parse(json['createdAt']),
      cancelledAt: parse(json['cancelledAt']),
    );
  }
}

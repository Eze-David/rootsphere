/// One line on a quotation, e.g. "Archive search — Enugu State" ₦25,000.
class QuoteLineItem {
  const QuoteLineItem({required this.description, required this.amountCents});

  final String description;

  /// Smallest currency unit (kobo for NGN).
  final int amountCents;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'description': description,
    'amount_cents': amountCents,
  };

  factory QuoteLineItem.fromJson(Map<String, dynamic> json) => QuoteLineItem(
    description: json['description'] as String? ?? '',
    amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
  );
}

enum QuotationStatus { sent, accepted, declined, paid, superseded }

/// An itemised quotation RootSphere sends a requester after reviewing their
/// research request. Written only through the `send_research_quotation` /
/// `respond_research_quotation` RPCs and the payment webhook — see
/// 20261014000000_research_quotations.sql.
class ResearchQuotation {
  const ResearchQuotation({
    required this.id,
    required this.opportunityId,
    required this.lineItems,
    required this.totalCents,
    required this.currency,
    required this.timeframe,
    required this.notes,
    required this.status,
    required this.createdAt,
    this.validUntil,
    this.declineReason,
    this.respondedAt,
    this.paidAt,
  });

  final String id;
  final String opportunityId;
  final List<QuoteLineItem> lineItems;
  final int totalCents;
  final String currency;
  final String timeframe;
  final String notes;
  final QuotationStatus status;
  final DateTime createdAt;
  final DateTime? validUntil;
  final String? declineReason;
  final DateTime? respondedAt;
  final DateTime? paidAt;

  bool get isExpired {
    if (validUntil == null) return false;
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return validUntil!.isBefore(today);
  }

  /// Short reference shown on screen and on the printed quotation.
  String get reference {
    final String compact = id.replaceAll('-', '').toUpperCase();
    return 'QT-${compact.substring(0, compact.length < 8 ? compact.length : 8)}';
  }

  factory ResearchQuotation.fromRow(Map<String, dynamic> row) {
    DateTime? date(String key) =>
        row[key] == null ? null : DateTime.tryParse(row[key].toString());
    return ResearchQuotation(
      id: row['id'] as String,
      opportunityId: row['opportunity_id'] as String,
      lineItems: (row['line_items'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (e) => QuoteLineItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      totalCents: (row['total_cents'] as num).toInt(),
      currency: row['currency'] as String? ?? 'ngn',
      timeframe: row['timeframe'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      status: QuotationStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => QuotationStatus.sent,
      ),
      createdAt: date('created_at')?.toLocal() ?? DateTime.now(),
      validUntil: date('valid_until'),
      declineReason: row['decline_reason'] as String?,
      respondedAt: date('responded_at')?.toLocal(),
      paidAt: date('paid_at')?.toLocal(),
    );
  }
}

/// "₦25,000" / "₦25,000.50" from kobo.
String formatNaira(int cents) {
  final int whole = cents ~/ 100;
  final int kobo = cents % 100;
  final String digits = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return kobo == 0 ? '₦$digits' : '₦$digits.${kobo.toString().padLeft(2, '0')}';
}

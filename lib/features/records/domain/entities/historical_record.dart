import 'record.dart';

/// A search query against an external historical-records provider
/// (FamilySearch). Scoped to a [RecordType] chosen from the Records chips.
class RecordSearchQuery {
  const RecordSearchQuery({
    this.type,
    this.firstName = '',
    this.lastName = '',
    this.place = '',
    this.year,
  });

  /// The record type being searched, or null to search across all types.
  final RecordType? type;
  final String firstName;
  final String lastName;

  /// Birth/event place ("City, County, State, Country").
  final String place;

  /// Birth/event year.
  final int? year;

  bool get isEmpty =>
      firstName.trim().isEmpty &&
      lastName.trim().isEmpty &&
      place.trim().isEmpty &&
      year == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type?.name ?? 'all',
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'place': place.trim(),
    'year': year,
  };
}

/// A single result returned by the external records search. Normalised from the
/// provider's response (GEDCOM X) by the `records-search` edge function so the
/// client stays provider-agnostic.
class HistoricalRecord {
  const HistoricalRecord({
    required this.id,
    required this.name,
    this.type = RecordType.other,
    this.eventDate,
    this.eventPlace,
    this.collection,
    this.sourceUrl,
    this.source,
  });

  final String id;
  final String name;
  final RecordType type;

  /// Free-text event date as returned by the provider (e.g. "12 March 1918").
  final String? eventDate;
  final String? eventPlace;

  /// The collection / archive the record belongs to.
  final String? collection;

  /// A link to the record on the provider's site, when available.
  final String? sourceUrl;

  /// The provider this result came from (e.g. "FamilySearch", "Wikidata").
  final String? source;

  /// Subtitle for result cards: "collection · place · date".
  String get subtitle => <String>[
    if ((collection ?? '').trim().isNotEmpty) collection!.trim(),
    if ((eventPlace ?? '').trim().isNotEmpty) eventPlace!.trim(),
    if ((eventDate ?? '').trim().isNotEmpty) eventDate!.trim(),
  ].join(' · ');

  factory HistoricalRecord.fromJson(Map<String, dynamic> json) {
    return HistoricalRecord(
      id:
          json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Unknown',
      type: RecordType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecordType.other,
      ),
      eventDate: json['eventDate'] as String?,
      eventPlace: json['eventPlace'] as String?,
      collection: json['collection'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      source: json['source'] as String?,
    );
  }
}

/// The outcome of a historical-records search.
class RecordSearchResult {
  const RecordSearchResult({
    this.records = const <HistoricalRecord>[],
    this.available = true,
    this.message,
  });

  final List<HistoricalRecord> records;

  /// False when the search provider can't be reached (Supabase not configured,
  /// function not deployed, or credentials missing) so the UI can guide the
  /// user rather than show an error.
  final bool available;
  final String? message;
}

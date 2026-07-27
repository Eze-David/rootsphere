import 'package:flutter/material.dart';

/// Genealogical record types (brief §Phase 3). Mirrors the filter chips on the
/// Records library mockup plus a few common archival categories.
enum RecordType {
  birth,
  marriage,
  death,
  census,
  military,
  immigration,
  baptism,
  photo,
  newspaper,
  community,
  cemetery,
  school,
  exam,
  church,
  transportManifest,
  library,
  museum,
  archive,
  landDocument,
  will,
  cooperativeAssociation,
  politicalPartyRegister,
  okadaUnion,
  marketAssociation,
  hospital,
  flightManifest,
  recruitmentAgency,
  other,
}

extension RecordTypeX on RecordType {
  /// Short label used on chips and badges.
  String get label {
    switch (this) {
      case RecordType.birth:
        return 'Birth';
      case RecordType.marriage:
        return 'Marriage';
      case RecordType.death:
        return 'Death';
      case RecordType.census:
        return 'Census';
      case RecordType.military:
        return 'Military';
      case RecordType.immigration:
        return 'Immigration';
      case RecordType.baptism:
        return 'Baptism';
      case RecordType.photo:
        return 'Photo';
      case RecordType.newspaper:
        return 'Newspaper';
      case RecordType.community:
        return 'Community';
      case RecordType.cemetery:
        return 'Cemetery';
      case RecordType.school:
        return 'School';
      case RecordType.exam:
        return 'Exam';
      case RecordType.church:
        return 'Church';
      case RecordType.transportManifest:
        return 'Transportation manifest';
      case RecordType.library:
        return 'Library';
      case RecordType.museum:
        return 'Museum';
      case RecordType.archive:
        return 'Archive';
      case RecordType.landDocument:
        return 'Land document';
      case RecordType.will:
        return 'Will';
      case RecordType.cooperativeAssociation:
        return 'Cooperative association';
      case RecordType.politicalPartyRegister:
        return 'Political party register';
      case RecordType.okadaUnion:
        return 'Okada union';
      case RecordType.marketAssociation:
        return 'Market association';
      case RecordType.hospital:
        return 'Hospital';
      case RecordType.flightManifest:
        return 'Flight manifest';
      case RecordType.recruitmentAgency:
        return 'Recruitment agency';
      case RecordType.other:
        return 'Other';
    }
  }

  /// Default human title prefix shown on cards, e.g. "Birth cert".
  String get cardPrefix {
    switch (this) {
      case RecordType.birth:
        return 'Birth cert';
      case RecordType.marriage:
        return 'Marriage cert';
      case RecordType.death:
        return 'Death cert';
      case RecordType.census:
        return 'Census';
      case RecordType.military:
        return 'Military';
      case RecordType.immigration:
        return 'Immigration';
      case RecordType.baptism:
        return 'Baptism';
      case RecordType.photo:
        return 'Photo';
      case RecordType.newspaper:
        return 'Newspaper';
      case RecordType.community:
        return 'Community record';
      case RecordType.cemetery:
        return 'Cemetery record';
      case RecordType.school:
        return 'School record';
      case RecordType.exam:
        return 'Exam record';
      case RecordType.church:
        return 'Church record';
      case RecordType.transportManifest:
        return 'Transportation manifest';
      case RecordType.library:
        return 'Library record';
      case RecordType.museum:
        return 'Museum record';
      case RecordType.archive:
        return 'Archive record';
      case RecordType.landDocument:
        return 'Land document';
      case RecordType.will:
        return 'Will';
      case RecordType.cooperativeAssociation:
        return 'Cooperative association record';
      case RecordType.politicalPartyRegister:
        return 'Political party register';
      case RecordType.okadaUnion:
        return 'Okada union record';
      case RecordType.marketAssociation:
        return 'Market association record';
      case RecordType.hospital:
        return 'Hospital record';
      case RecordType.flightManifest:
        return 'Flight manifest';
      case RecordType.recruitmentAgency:
        return 'Recruitment agency record';
      case RecordType.other:
        return 'Record';
    }
  }

  IconData get icon {
    switch (this) {
      case RecordType.birth:
        return Icons.workspace_premium_outlined;
      case RecordType.marriage:
        return Icons.favorite_border;
      case RecordType.death:
        return Icons.local_florist_outlined;
      case RecordType.census:
        return Icons.description_outlined;
      case RecordType.military:
        return Icons.military_tech_outlined;
      case RecordType.immigration:
        return Icons.directions_boat_outlined;
      case RecordType.baptism:
        return Icons.water_drop_outlined;
      case RecordType.photo:
        return Icons.photo_outlined;
      case RecordType.newspaper:
        return Icons.newspaper_outlined;
      case RecordType.community:
        return Icons.people_outline;
      case RecordType.cemetery:
        return Icons.location_city_outlined;
      case RecordType.school:
        return Icons.school_outlined;
      case RecordType.exam:
        return Icons.assignment_outlined;
      case RecordType.church:
        return Icons.church_outlined;
      case RecordType.transportManifest:
        return Icons.confirmation_number_outlined;
      case RecordType.library:
        return Icons.local_library_outlined;
      case RecordType.museum:
        return Icons.museum_outlined;
      case RecordType.archive:
        return Icons.archive_outlined;
      case RecordType.landDocument:
        return Icons.landscape_outlined;
      case RecordType.will:
        return Icons.gavel_outlined;
      case RecordType.cooperativeAssociation:
        return Icons.groups_outlined;
      case RecordType.politicalPartyRegister:
        return Icons.how_to_vote_outlined;
      case RecordType.okadaUnion:
        return Icons.two_wheeler_outlined;
      case RecordType.marketAssociation:
        return Icons.storefront_outlined;
      case RecordType.hospital:
        return Icons.local_hospital_outlined;
      case RecordType.flightManifest:
        return Icons.flight_outlined;
      case RecordType.recruitmentAgency:
        return Icons.work_outline;
      case RecordType.other:
        return Icons.article_outlined;
    }
  }
}

/// The kind of media a record's attachment is, derived from its file extension.
/// Drives how the detail screen renders the attachment.
enum RecordMediaKind { image, pdf, document, none }

/// A source document / media item attached to a family tree (brief §Phase 3).
///
/// Relationships to people are stored as id references ([personIds]) so a
/// single record (e.g. a census page) can cite multiple individuals. The
/// attachment itself lives in Supabase Storage (or a local file in demo mode);
/// [fileUrl] is an [AdaptiveImage]-compatible reference.
class Record {
  const Record({
    required this.id,
    required this.treeId,
    required this.type,
    required this.title,
    this.repository = '',
    this.date,
    this.fileUrl,
    this.fileName,
    this.ocrText,
    this.citationOverride,
    this.notes,
    this.personIds = const <String>[],
    this.createdAt,
    this.aiSummary,
    this.aiTranslation,
    this.aiTranslationLang,
    this.aiLocations = const <String>[],
  });

  final String id;
  final String treeId;
  final RecordType type;

  /// Subject of the record, e.g. "Adaeze Okonkwo" or "Emeka & Ngozi".
  final String title;

  /// Holding institution / archive, e.g. "Lagos State Registry".
  final String repository;

  /// The date the recorded event occurred (year is shown on cards).
  final DateTime? date;

  /// Reference to the stored attachment (public URL or local path).
  final String? fileUrl;
  final String? fileName;

  /// Text extracted from the attachment via OCR (null until run).
  final String? ocrText;

  /// A manually-edited citation that overrides the generated one.
  final String? citationOverride;

  final String? notes;
  final List<String> personIds;
  final DateTime? createdAt;

  /// AI Assistant results, cached so revisiting the record doesn't re-charge
  /// the Claude API (null/empty until the corresponding action has been run).
  final String? aiSummary;
  final String? aiTranslation;
  final String? aiTranslationLang;
  final List<String> aiLocations;

  int? get year => date?.year;

  RecordMediaKind get mediaKind {
    final String name = (fileName ?? fileUrl ?? '').toLowerCase();
    if (name.isEmpty) return RecordMediaKind.none;
    final int dot = name.lastIndexOf('.');
    final String ext = dot >= 0 ? name.substring(dot + 1) : '';
    const Set<String> images = <String>{
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'bmp',
    };
    if (images.contains(ext)) return RecordMediaKind.image;
    if (ext == 'pdf') return RecordMediaKind.pdf;
    if (ext.isEmpty) return RecordMediaKind.none;
    return RecordMediaKind.document;
  }

  bool get hasImage => mediaKind == RecordMediaKind.image && fileUrl != null;

  /// Whether the `ocr` edge function can pull text from this attachment —
  /// true OCR for images/PDFs, direct XML extraction for .docx (see
  /// supabase/functions/ocr). Other document types (.doc, .txt, ...) aren't
  /// supported.
  bool get canExtractText {
    if (fileUrl == null) return false;
    switch (mediaKind) {
      case RecordMediaKind.image:
      case RecordMediaKind.pdf:
        return true;
      case RecordMediaKind.document:
        return (fileName ?? fileUrl ?? '').toLowerCase().endsWith('.docx');
      case RecordMediaKind.none:
        return false;
    }
  }

  /// The card title, e.g. "Birth cert · Adaeze Okonkwo".
  String get displayTitle =>
      title.isEmpty ? type.cardPrefix : '${type.cardPrefix} · $title';

  /// The card subtitle, e.g. "Lagos State Registry · 1986".
  String get subtitle {
    final List<String> parts = <String>[
      if (repository.trim().isNotEmpty) repository.trim(),
      if (year != null) '$year',
    ];
    return parts.join(' · ');
  }

  /// An evidence-style citation, either the manual override or one generated
  /// from the structured fields.
  String get citation {
    if (citationOverride != null && citationOverride!.trim().isNotEmpty) {
      return citationOverride!.trim();
    }
    final List<String> parts = <String>[];
    final String subject = title.trim();
    final String typeLabel = type.label;
    if (subject.isNotEmpty) {
      parts.add('$typeLabel record for $subject');
    } else {
      parts.add('$typeLabel record');
    }
    if (repository.trim().isNotEmpty) parts.add(repository.trim());
    if (year != null) parts.add('$year');
    return '${parts.join(', ')}.';
  }

  Record copyWith({
    RecordType? type,
    String? title,
    String? repository,
    Object? date = _sentinel,
    Object? fileUrl = _sentinel,
    Object? fileName = _sentinel,
    Object? ocrText = _sentinel,
    Object? citationOverride = _sentinel,
    Object? notes = _sentinel,
    List<String>? personIds,
    DateTime? createdAt,
    Object? aiSummary = _sentinel,
    Object? aiTranslation = _sentinel,
    Object? aiTranslationLang = _sentinel,
    List<String>? aiLocations,
  }) {
    return Record(
      id: id,
      treeId: treeId,
      type: type ?? this.type,
      title: title ?? this.title,
      repository: repository ?? this.repository,
      date: date == _sentinel ? this.date : date as DateTime?,
      fileUrl: fileUrl == _sentinel ? this.fileUrl : fileUrl as String?,
      fileName: fileName == _sentinel ? this.fileName : fileName as String?,
      ocrText: ocrText == _sentinel ? this.ocrText : ocrText as String?,
      citationOverride: citationOverride == _sentinel
          ? this.citationOverride
          : citationOverride as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      personIds: personIds ?? this.personIds,
      createdAt: createdAt ?? this.createdAt,
      aiSummary: aiSummary == _sentinel ? this.aiSummary : aiSummary as String?,
      aiTranslation: aiTranslation == _sentinel
          ? this.aiTranslation
          : aiTranslation as String?,
      aiTranslationLang: aiTranslationLang == _sentinel
          ? this.aiTranslationLang
          : aiTranslationLang as String?,
      aiLocations: aiLocations ?? this.aiLocations,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'treeId': treeId,
    'type': type.name,
    'title': title,
    'repository': repository,
    'date': date?.toIso8601String(),
    'fileUrl': fileUrl,
    'fileName': fileName,
    'ocrText': ocrText,
    'citationOverride': citationOverride,
    'notes': notes,
    'personIds': personIds,
    'createdAt': createdAt?.toIso8601String(),
    'aiSummary': aiSummary,
    'aiTranslation': aiTranslation,
    'aiTranslationLang': aiTranslationLang,
    'aiLocations': aiLocations,
  };

  factory Record.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return Record(
      id: json['id'] as String,
      treeId: json['treeId'] as String,
      type: RecordType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecordType.other,
      ),
      title: json['title'] as String? ?? '',
      repository: json['repository'] as String? ?? '',
      date: parse(json['date']),
      fileUrl: json['fileUrl'] as String?,
      fileName: json['fileName'] as String?,
      ocrText: json['ocrText'] as String?,
      citationOverride: json['citationOverride'] as String?,
      notes: json['notes'] as String?,
      personIds: (json['personIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      aiSummary: json['aiSummary'] as String?,
      aiTranslation: json['aiTranslation'] as String?,
      aiTranslationLang: json['aiTranslationLang'] as String?,
      aiLocations: (json['aiLocations'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      createdAt: parse(json['createdAt']),
    );
  }

  static const Object _sentinel = Object();
}

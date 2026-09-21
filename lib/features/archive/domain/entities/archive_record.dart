import '../../../records/domain/entities/record.dart';

/// Where a record sits in the admin curation workflow (mockup steps 1–4:
/// Upload/Describe leave it as [draft], Review moves it to [pendingReview],
/// and an admin's Approve/Reject during Catalogue resolves it to [published]
/// or [rejected]).
enum ArchiveReviewStatus { draft, pendingReview, published, rejected }

extension ArchiveReviewStatusX on ArchiveReviewStatus {
  String get label {
    switch (this) {
      case ArchiveReviewStatus.draft:
        return 'Draft';
      case ArchiveReviewStatus.pendingReview:
        return 'Pending review';
      case ArchiveReviewStatus.published:
        return 'Published';
      case ArchiveReviewStatus.rejected:
        return 'Rejected';
    }
  }
}

/// How a published record's attachments can be reached: viewable right away
/// ([online]), only after a user requests access and an admin approves it
/// ([permission] — approving flips the record to [online] for everyone,
/// there's no per-user file ACL), or catalogued with nothing digitized yet
/// ([archive] — a research pointer to where the record is physically held).
enum ArchiveAccessStatus { online, permission, archive }

extension ArchiveAccessStatusX on ArchiveAccessStatus {
  String get label {
    switch (this) {
      case ArchiveAccessStatus.online:
        return 'Online';
      case ArchiveAccessStatus.permission:
        return 'Permission';
      case ArchiveAccessStatus.archive:
        return 'Archive';
    }
  }
}

/// The role a stored attachment plays — the mockup's "Master scan + web
/// copy" distinction (this pass stores whatever the admin uploads under
/// either tag; no automatic web-copy transcoding).
enum ArchiveFileKind { master, supporting }

/// A single attachment on an [ArchiveRecord].
class ArchiveFile {
  const ArchiveFile({
    required this.url,
    required this.fileName,
    this.kind = ArchiveFileKind.master,
  });

  final String url;
  final String fileName;
  final ArchiveFileKind kind;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'fileName': fileName,
    'kind': kind.name,
  };

  factory ArchiveFile.fromJson(Map<String, dynamic> json) => ArchiveFile(
    url: json['url'] as String,
    fileName: json['fileName'] as String? ?? '',
    kind: ArchiveFileKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ArchiveFileKind.master,
    ),
  );
}

/// A catalogued entry in the admin-only Digital Records Repository —
/// distinct from [Record] (a source document a user attaches to their own
/// tree): this belongs to a [collection] scoped by [country]/[stateRegion],
/// not a tree, and goes through an explicit review workflow before it's
/// considered part of the searchable archive.
class ArchiveRecord {
  const ArchiveRecord({
    required this.id,
    this.recordRef,
    this.title = '',
    this.type = RecordType.other,
    this.collection = '',
    this.country = '',
    this.stateRegion = '',
    this.locality = '',
    this.dateRangeStart,
    this.dateRangeEnd,
    this.repositorySource = '',
    this.contributor = '',
    this.keywords = const <String>[],
    this.description,
    this.files = const <ArchiveFile>[],
    this.searchText,
    this.accessStatus = ArchiveAccessStatus.permission,
    this.reviewStatus = ArchiveReviewStatus.draft,
    this.reviewerNote,
    this.createdBy,
    this.reviewedBy,
    this.createdAt,
    this.updatedAt,
    this.reviewedAt,
  });

  final String id;

  /// Catalogue reference, e.g. "RS-NGA-BEN-BIR-000142" — assigned server-side
  /// the first time the record is submitted for review; null on drafts.
  final String? recordRef;

  final String title;
  final RecordType type;
  final String collection;
  final String country;
  final String stateRegion;
  final String locality;
  final int? dateRangeStart;
  final int? dateRangeEnd;
  final String repositorySource;
  final String contributor;
  final List<String> keywords;
  final String? description;
  final List<ArchiveFile> files;

  /// OCR text plus the manually-entered keywords/description, concatenated
  /// for free-text search on the Stored collections tab.
  final String? searchText;

  final ArchiveAccessStatus accessStatus;
  final ArchiveReviewStatus reviewStatus;
  final String? reviewerNote;
  final String? createdBy;
  final String? reviewedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? reviewedAt;

  String get dateRangeLabel {
    if (dateRangeStart == null && dateRangeEnd == null) return '';
    if (dateRangeStart != null && dateRangeEnd != null) {
      return dateRangeStart == dateRangeEnd
          ? '$dateRangeStart'
          : '$dateRangeStart–$dateRangeEnd';
    }
    return '${dateRangeStart ?? dateRangeEnd}';
  }

  String get displayTitle =>
      title.trim().isEmpty ? type.cardPrefix : title.trim();

  ArchiveRecord copyWith({
    Object? recordRef = _sentinel,
    String? title,
    RecordType? type,
    String? collection,
    String? country,
    String? stateRegion,
    String? locality,
    Object? dateRangeStart = _sentinel,
    Object? dateRangeEnd = _sentinel,
    String? repositorySource,
    String? contributor,
    List<String>? keywords,
    Object? description = _sentinel,
    List<ArchiveFile>? files,
    Object? searchText = _sentinel,
    ArchiveAccessStatus? accessStatus,
    ArchiveReviewStatus? reviewStatus,
    Object? reviewerNote = _sentinel,
    String? createdBy,
    Object? reviewedBy = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? reviewedAt = _sentinel,
  }) {
    return ArchiveRecord(
      id: id,
      recordRef: recordRef == _sentinel ? this.recordRef : recordRef as String?,
      title: title ?? this.title,
      type: type ?? this.type,
      collection: collection ?? this.collection,
      country: country ?? this.country,
      stateRegion: stateRegion ?? this.stateRegion,
      locality: locality ?? this.locality,
      dateRangeStart: dateRangeStart == _sentinel
          ? this.dateRangeStart
          : dateRangeStart as int?,
      dateRangeEnd: dateRangeEnd == _sentinel
          ? this.dateRangeEnd
          : dateRangeEnd as int?,
      repositorySource: repositorySource ?? this.repositorySource,
      contributor: contributor ?? this.contributor,
      keywords: keywords ?? this.keywords,
      description: description == _sentinel
          ? this.description
          : description as String?,
      files: files ?? this.files,
      searchText: searchText == _sentinel ? this.searchText : searchText as String?,
      accessStatus: accessStatus ?? this.accessStatus,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      reviewerNote: reviewerNote == _sentinel
          ? this.reviewerNote
          : reviewerNote as String?,
      createdBy: createdBy ?? this.createdBy,
      reviewedBy: reviewedBy == _sentinel ? this.reviewedBy : reviewedBy as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedAt: reviewedAt == _sentinel ? this.reviewedAt : reviewedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'recordRef': recordRef,
    'title': title,
    'type': type.name,
    'collection': collection,
    'country': country,
    'stateRegion': stateRegion,
    'locality': locality,
    'dateRangeStart': dateRangeStart,
    'dateRangeEnd': dateRangeEnd,
    'repositorySource': repositorySource,
    'contributor': contributor,
    'keywords': keywords,
    'description': description,
    'files': files.map((f) => f.toJson()).toList(),
    'searchText': searchText,
    'accessStatus': accessStatus.name,
    'reviewStatus': reviewStatus.name,
    'reviewerNote': reviewerNote,
    'createdBy': createdBy,
    'reviewedBy': reviewedBy,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'reviewedAt': reviewedAt?.toIso8601String(),
  };

  factory ArchiveRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return ArchiveRecord(
      id: json['id'] as String,
      recordRef: json['recordRef'] as String?,
      title: json['title'] as String? ?? '',
      type: RecordType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecordType.other,
      ),
      collection: json['collection'] as String? ?? '',
      country: json['country'] as String? ?? '',
      stateRegion: json['stateRegion'] as String? ?? '',
      locality: json['locality'] as String? ?? '',
      dateRangeStart: json['dateRangeStart'] as int?,
      dateRangeEnd: json['dateRangeEnd'] as int?,
      repositorySource: json['repositorySource'] as String? ?? '',
      contributor: json['contributor'] as String? ?? '',
      keywords: (json['keywords'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      description: json['description'] as String?,
      files: (json['files'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => ArchiveFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      searchText: json['searchText'] as String?,
      accessStatus: ArchiveAccessStatus.values.firstWhere(
        (a) => a.name == json['accessStatus'],
        orElse: () => ArchiveAccessStatus.permission,
      ),
      reviewStatus: ArchiveReviewStatus.values.firstWhere(
        (s) => s.name == json['reviewStatus'],
        orElse: () => ArchiveReviewStatus.draft,
      ),
      reviewerNote: json['reviewerNote'] as String?,
      createdBy: json['createdBy'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
      createdAt: parse(json['createdAt']),
      updatedAt: parse(json['updatedAt']),
      reviewedAt: parse(json['reviewedAt']),
    );
  }

  static const Object _sentinel = Object();
}

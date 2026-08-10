import 'record.dart';

/// A privacy-safe match returned by the global (cross-tree) record search RPC
/// `search_records_global` — a record nobody has linked to a person, so it's
/// treated as a standalone community contribution any signed-in user can find
/// and copy into their own tree. Never exposes who uploaded it or their
/// private notes.
class GlobalRecordMatch {
  const GlobalRecordMatch({
    required this.id,
    this.type = RecordType.other,
    this.title = '',
    this.repository = '',
    this.eventDate,
    this.fileUrl,
    this.fileName,
    this.ocrText,
    this.createdAt,
  });

  final String id;
  final RecordType type;
  final String title;
  final String repository;
  final DateTime? eventDate;
  final String? fileUrl;
  final String? fileName;
  final String? ocrText;
  final DateTime? createdAt;

  int? get year => eventDate?.year;

  String get displayTitle =>
      title.isEmpty ? type.cardPrefix : '${type.cardPrefix} · $title';

  /// "Lagos State Registry · 1986"
  String get subtitle {
    final List<String> parts = <String>[
      if (repository.trim().isNotEmpty) repository.trim(),
      if (year != null) '$year',
    ];
    return parts.join(' · ');
  }

  /// Same extension-sniffing as [Record.mediaKind] — used to decide whether
  /// "View" shows an image, a PDF viewer, or an extracted-text reader.
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

  /// An evidence-style citation, mirroring [Record.citation] (no override
  /// concept here — this is someone else's record, not editable).
  String get citation {
    final List<String> parts = <String>[];
    final String subject = title.trim();
    final String typeLabel = type.label;
    parts.add(subject.isNotEmpty ? '$typeLabel record for $subject' : '$typeLabel record');
    if (repository.trim().isNotEmpty) parts.add(repository.trim());
    if (year != null) parts.add('$year');
    return '${parts.join(', ')}.';
  }

  factory GlobalRecordMatch.fromRow(Map<String, dynamic> row) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return GlobalRecordMatch(
      id: row['id'].toString(),
      type: RecordType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => RecordType.other,
      ),
      title: row['title'] as String? ?? '',
      repository: row['repository'] as String? ?? '',
      eventDate: parse(row['event_date']),
      fileUrl: row['file_url'] as String?,
      fileName: row['file_name'] as String?,
      ocrText: row['ocr_text'] as String?,
      createdAt: parse(row['created_at']),
    );
  }
}

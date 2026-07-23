/// Quality-control checkpoint for an Indexer transcription.
enum QualityCheck { textLegible, matchesImage, fieldsComplete }

extension QualityCheckX on QualityCheck {
  String get label {
    switch (this) {
      case QualityCheck.textLegible:
        return 'Text is legible';
      case QualityCheck.matchesImage:
        return 'Transcription matches image';
      case QualityCheck.fieldsComplete:
        return 'All fields are complete';
    }
  }
}

/// Structured transcription/indexing output submitted by an Indexer.
class IndexerSubmission {
  const IndexerSubmission({
    this.transcription,
    this.originalImageUrl,
    this.qualityChecks = const <QualityCheck>[],
    this.keywords,
    this.notes,
  });

  final String? transcription;
  final String? originalImageUrl;
  final List<QualityCheck> qualityChecks;

  /// Comma-separated or list of keyword tags.
  final String? keywords;
  final String? notes;

  bool get isEmpty {
    return (transcription == null || transcription!.isEmpty) &&
        (originalImageUrl == null || originalImageUrl!.isEmpty) &&
        qualityChecks.isEmpty &&
        (keywords == null || keywords!.isEmpty) &&
        (notes == null || notes!.isEmpty);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'transcription': transcription,
    'originalImageUrl': originalImageUrl,
    'qualityChecks': qualityChecks.map((q) => q.name).toList(),
    'keywords': keywords,
    'notes': notes,
  };

  factory IndexerSubmission.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const IndexerSubmission();
    return IndexerSubmission(
      transcription: json['transcription'] as String?,
      originalImageUrl: json['originalImageUrl'] as String?,
      qualityChecks: json['qualityChecks'] == null
          ? const <QualityCheck>[]
          : (json['qualityChecks'] as List<dynamic>)
                .map(
                  (e) => QualityCheck.values.firstWhere(
                    (q) => q.name == e,
                    orElse: () => QualityCheck.textLegible,
                  ),
                )
                .toList(),
      keywords: json['keywords'] as String?,
      notes: json['notes'] as String?,
    );
  }

  IndexerSubmission copyWith({
    String? transcription,
    String? originalImageUrl,
    List<QualityCheck>? qualityChecks,
    String? keywords,
    String? notes,
  }) {
    return IndexerSubmission(
      transcription: transcription ?? this.transcription,
      originalImageUrl: originalImageUrl ?? this.originalImageUrl,
      qualityChecks: qualityChecks ?? this.qualityChecks,
      keywords: keywords ?? this.keywords,
      notes: notes ?? this.notes,
    );
  }
}

/// A single source/document discovered by a Finder.
class ResearchSource {
  const ResearchSource({this.title = '', this.url, this.date, this.notes});

  final String title;
  final String? url;
  final String? date;
  final String? notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'url': url,
    'date': date,
    'notes': notes,
  };

  factory ResearchSource.fromJson(Map<String, dynamic> json) {
    return ResearchSource(
      title: json['title'] as String? ?? '',
      url: json['url'] as String?,
      date: json['date'] as String?,
      notes: json['notes'] as String?,
    );
  }

  ResearchSource copyWith({
    String? title,
    String? url,
    String? date,
    String? notes,
  }) {
    return ResearchSource(
      title: title ?? this.title,
      url: url ?? this.url,
      date: date ?? this.date,
      notes: notes ?? this.notes,
    );
  }
}

/// Structured research output submitted by a Finder.
class FinderSubmission {
  const FinderSubmission({
    this.summary,
    this.sources = const <ResearchSource>[],
    this.evidenceNotes,
    this.confidenceLevel,
    this.dnaNotes,
    this.report,
  });

  final String? summary;
  final List<ResearchSource> sources;
  final String? evidenceNotes;

  /// e.g. high / medium / low
  final String? confidenceLevel;
  final String? dnaNotes;

  /// Compiled report or chart text.
  final String? report;

  bool get isEmpty {
    return (summary == null || summary!.isEmpty) &&
        sources.isEmpty &&
        (evidenceNotes == null || evidenceNotes!.isEmpty) &&
        (confidenceLevel == null || confidenceLevel!.isEmpty) &&
        (dnaNotes == null || dnaNotes!.isEmpty) &&
        (report == null || report!.isEmpty);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'summary': summary,
    'sources': sources.map((s) => s.toJson()).toList(),
    'evidenceNotes': evidenceNotes,
    'confidenceLevel': confidenceLevel,
    'dnaNotes': dnaNotes,
    'report': report,
  };

  factory FinderSubmission.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FinderSubmission();
    return FinderSubmission(
      summary: json['summary'] as String?,
      sources: json['sources'] == null
          ? const <ResearchSource>[]
          : (json['sources'] as List<dynamic>)
                .map((e) => ResearchSource.fromJson(e as Map<String, dynamic>))
                .toList(),
      evidenceNotes: json['evidenceNotes'] as String?,
      confidenceLevel: json['confidenceLevel'] as String?,
      dnaNotes: json['dnaNotes'] as String?,
      report: json['report'] as String?,
    );
  }

  FinderSubmission copyWith({
    String? summary,
    List<ResearchSource>? sources,
    String? evidenceNotes,
    String? confidenceLevel,
    String? dnaNotes,
    String? report,
  }) {
    return FinderSubmission(
      summary: summary ?? this.summary,
      sources: sources ?? this.sources,
      evidenceNotes: evidenceNotes ?? this.evidenceNotes,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
      dnaNotes: dnaNotes ?? this.dnaNotes,
      report: report ?? this.report,
    );
  }
}

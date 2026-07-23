/// Generic outcome of an AI Assistant call (see `assistant` Edge Function).
///
/// Mirrors the graceful-degradation shape already used by hints/OCR: [data]
/// carries the parsed result on success, while [available] is false (with a
/// human-readable [message]) when Claude is unconfigured, unreachable, or the
/// server-side cooldown blocked the request.
class AssistantResponse<T> {
  const AssistantResponse({required this.available, this.message, this.data});

  final bool available;
  final String? message;
  final T? data;

  bool get hasData {
    final T? d = data;
    if (d == null) return false;
    if (d is String) return d.trim().isNotEmpty;
    if (d is Iterable) return d.isNotEmpty;
    return true;
  }
}

/// A suggested ancestor/relative that appears to be missing from the tree.
class AncestorSuggestion {
  const AncestorSuggestion({
    required this.relation,
    required this.reasoning,
    required this.confidence,
  });

  final String relation;
  final String reasoning;
  final int confidence;

  factory AncestorSuggestion.fromJson(Map<String, dynamic> json) {
    return AncestorSuggestion(
      relation: json['relation']?.toString() ?? '',
      reasoning: json['reasoning']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.round() ?? 50,
    );
  }
}

/// A single entry in an AI-generated biographical timeline.
class TimelineEntry {
  const TimelineEntry({this.year, required this.title, required this.description});

  final int? year;
  final String title;
  final String description;

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    return TimelineEntry(
      year: (json['year'] as num?)?.round(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

/// A suggested record type worth searching for, with the reasoning behind it.
class MissingRecordSuggestion {
  const MissingRecordSuggestion({
    required this.type,
    required this.reasoning,
    required this.confidence,
  });

  final String type;
  final String reasoning;
  final int confidence;

  factory MissingRecordSuggestion.fromJson(Map<String, dynamic> json) {
    return MissingRecordSuggestion(
      type: json['type']?.toString() ?? '',
      reasoning: json['reasoning']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.round() ?? 50,
    );
  }
}

/// A concrete next research step.
class ResearchRecommendation {
  const ResearchRecommendation({required this.title, required this.description});

  final String title;
  final String description;

  factory ResearchRecommendation.fromJson(Map<String, dynamic> json) {
    return ResearchRecommendation(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

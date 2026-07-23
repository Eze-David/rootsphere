import 'package:flutter/material.dart';

/// The kind of suggestion a [Hint] represents (brief §Phase 4 — Hints & AI).
enum HintType { missingData, duplicate, recordMatch, relationship }

/// Lifecycle of a hint as the user triages it.
enum HintStatus { pending, accepted, dismissed }

/// How a [HintType.relationship] hint should be applied.
enum HintRelation { parent, child, spouse }

extension HintTypeX on HintType {
  String get label {
    switch (this) {
      case HintType.missingData:
        return 'Missing data';
      case HintType.duplicate:
        return 'Possible duplicate';
      case HintType.recordMatch:
        return 'Record match';
      case HintType.relationship:
        return 'Relationship';
    }
  }

  IconData get icon {
    switch (this) {
      case HintType.missingData:
        return Icons.edit_note_outlined;
      case HintType.duplicate:
        return Icons.people_alt_outlined;
      case HintType.recordMatch:
        return Icons.description_outlined;
      case HintType.relationship:
        return Icons.account_tree_outlined;
    }
  }
}

/// A confidence-ranked, AI- or heuristic-generated suggestion about a person in
/// a family tree. Generated server-side (Claude via the `hints` Edge Function)
/// and/or locally in a background isolate, then triaged by the user
/// (accept → apply the change, or dismiss).
class Hint {
  const Hint({
    required this.id,
    required this.treeId,
    required this.type,
    required this.title,
    required this.description,
    required this.confidence,
    this.status = HintStatus.pending,
    this.source = 'local',
    this.personId,
    this.relatedPersonId,
    this.recordId,
    this.field,
    this.suggestedValue,
    this.relation,
    this.createdAt,
  });

  final String id;
  final String treeId;
  final HintType type;
  final String title;
  final String description;

  /// 0–100; higher means a stronger suggestion. Drives ranking.
  final int confidence;

  final HintStatus status;

  /// `ai` (Claude) or `local` (heuristic / isolate).
  final String source;

  /// The primary person this hint is about.
  final String? personId;

  /// A second person, for duplicates and relationship suggestions.
  final String? relatedPersonId;

  /// A record this hint links to (record-match hints).
  final String? recordId;

  /// For missing-data hints: the [Person] field to fill (e.g. `birthDate`).
  final String? field;

  /// For missing-data hints: the value to apply, when Claude inferred one.
  final String? suggestedValue;

  /// For relationship hints: how [relatedPersonId] relates to [personId].
  final HintRelation? relation;

  final DateTime? createdAt;

  /// Whether accepting this hint can directly apply a concrete change.
  bool get isApplicable {
    switch (type) {
      case HintType.recordMatch:
        return recordId != null && personId != null;
      case HintType.relationship:
        return relation != null && personId != null && relatedPersonId != null;
      case HintType.missingData:
        return field != null &&
            (suggestedValue?.trim().isNotEmpty ?? false) &&
            personId != null;
      case HintType.duplicate:
        return false; // Merging is destructive — reviewed manually.
    }
  }

  Hint copyWith({HintStatus? status}) {
    return Hint(
      id: id,
      treeId: treeId,
      type: type,
      title: title,
      description: description,
      confidence: confidence,
      status: status ?? this.status,
      source: source,
      personId: personId,
      relatedPersonId: relatedPersonId,
      recordId: recordId,
      field: field,
      suggestedValue: suggestedValue,
      relation: relation,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'treeId': treeId,
        'type': type.name,
        'title': title,
        'description': description,
        'confidence': confidence,
        'status': status.name,
        'source': source,
        'personId': personId,
        'relatedPersonId': relatedPersonId,
        'recordId': recordId,
        'field': field,
        'suggestedValue': suggestedValue,
        'relation': relation?.name,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory Hint.fromJson(Map<String, dynamic> json) {
    return Hint(
      id: json['id'] as String,
      treeId: json['treeId'] as String,
      type: HintType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => HintType.missingData,
      ),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.round() ?? 50,
      status: HintStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => HintStatus.pending,
      ),
      source: json['source'] as String? ?? 'local',
      personId: json['personId'] as String?,
      relatedPersonId: json['relatedPersonId'] as String?,
      recordId: json['recordId'] as String?,
      field: json['field'] as String?,
      suggestedValue: json['suggestedValue'] as String?,
      relation: json['relation'] == null
          ? null
          : HintRelation.values.firstWhere(
              (r) => r.name == json['relation'],
              orElse: () => HintRelation.parent,
            ),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

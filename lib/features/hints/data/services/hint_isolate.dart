import 'package:flutter/foundation.dart' show compute;

import '../../domain/entities/hint.dart';

/// Background hint processing (brief §Phase 4 — "Dart Isolate background
/// processing").
///
/// Detecting missing data and likely duplicates is an O(n²) scan over every
/// person, and merging/de-duplicating/ranking the combined AI + heuristic set
/// can be sizeable for large trees. [HintProcessor.run] performs all of that on
/// a background isolate via [compute] so the UI thread never janks.
class HintProcessor {
  HintProcessor._();

  /// Runs heuristic detection over [people]/[records], merges in [aiHints],
  /// de-duplicates and ranks the result by confidence — all off the main
  /// thread. Inputs/outputs are plain JSON so they cross the isolate boundary.
  static Future<List<Hint>> run({
    required String treeId,
    required List<Map<String, dynamic>> people,
    required List<Map<String, dynamic>> records,
    required List<Hint> aiHints,
  }) async {
    final List<Map<String, dynamic>> ranked = await compute(
      rankHintsIsolate,
      <String, dynamic>{
        'treeId': treeId,
        'people': people,
        'records': records,
        'aiHints': aiHints.map((h) => h.toJson()).toList(),
      },
    );
    return ranked.map(Hint.fromJson).toList();
  }
}

/// Top-level isolate entrypoint (required by [compute]). Generates local
/// heuristic hints, merges them with the AI hints, de-duplicates and ranks.
List<Map<String, dynamic>> rankHintsIsolate(Map<String, dynamic> payload) {
  final String treeId = payload['treeId'] as String;
  final List<Map<String, dynamic>> people = _maps(payload['people']);
  final List<Map<String, dynamic>> aiHints = _maps(payload['aiHints']);

  final List<Map<String, dynamic>> local = <Map<String, dynamic>>[];
  local.addAll(_missingDataHints(treeId, people));
  local.addAll(_duplicateHints(treeId, people));

  // Merge AI + local, de-duplicating by stable identity (AI wins on a tie so
  // its richer descriptions / suggested values are preserved).
  final Map<String, Map<String, dynamic>> byKey = <String, Map<String, dynamic>>{};
  for (final h in local) {
    byKey[_dedupeKey(h)] = h;
  }
  for (final h in aiHints) {
    byKey[_dedupeKey(h)] = h;
  }

  final List<Map<String, dynamic>> merged = byKey.values.toList();
  merged.sort((a, b) {
    final int ca = (a['confidence'] as num?)?.round() ?? 0;
    final int cb = (b['confidence'] as num?)?.round() ?? 0;
    return cb.compareTo(ca);
  });
  return merged;
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v as List<dynamic>? ?? const <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

String _dedupeKey(Map<String, dynamic> h) => <String>[
      h['type']?.toString() ?? '',
      h['personId']?.toString() ?? '',
      h['relatedPersonId']?.toString() ?? '',
      h['recordId']?.toString() ?? '',
      h['field']?.toString() ?? '',
    ].join('|');

// ── Heuristics ───────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _missingDataHints(
  String treeId,
  List<Map<String, dynamic>> people,
) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final p in people) {
    final String name = (p['name'] as String?)?.trim() ?? 'This person';
    final String id = p['id'] as String? ?? '';
    if (id.isEmpty) continue;

    final bool central = ((p['spouseIds'] as List<dynamic>?)?.isNotEmpty ?? false) ||
        ((p['parentIds'] as List<dynamic>?)?.isNotEmpty ?? false);

    if (p['birthYear'] == null) {
      out.add(_hint(
        id: 'local_birth_$id',
        treeId: treeId,
        type: 'missingData',
        title: 'Add a birth date for $name',
        description:
            '$name has no birth date recorded. Adding one improves timeline '
            'accuracy and record matching.',
        confidence: central ? 70 : 62,
        personId: id,
        field: 'birthDate',
      ));
    }
    final String? birthPlace = (p['birthPlace'] as String?)?.trim();
    if (birthPlace == null || birthPlace.isEmpty) {
      out.add(_hint(
        id: 'local_birthplace_$id',
        treeId: treeId,
        type: 'missingData',
        title: 'Add a birthplace for $name',
        description:
            '$name has no birthplace. Knowing where they were born helps '
            'surface local records.',
        confidence: 55,
        personId: id,
        field: 'birthPlace',
      ));
    }
  }
  return out;
}

List<Map<String, dynamic>> _duplicateHints(
  String treeId,
  List<Map<String, dynamic>> people,
) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (int i = 0; i < people.length; i++) {
    for (int j = i + 1; j < people.length; j++) {
      final a = people[i];
      final b = people[j];
      final String an = _normalize(a['name'] as String? ?? '');
      final String bn = _normalize(b['name'] as String? ?? '');
      if (an.isEmpty || bn.isEmpty || an != bn) continue;

      final String aId = a['id'] as String? ?? '';
      final String bId = b['id'] as String? ?? '';
      if (aId.isEmpty || bId.isEmpty) continue;

      // Birth years agreeing (or both unknown) raises confidence.
      final int? ay = (a['birthYear'] as num?)?.round();
      final int? by = (b['birthYear'] as num?)?.round();
      final bool yearsAgree = ay != null && by != null && ay == by;
      final int confidence = yearsAgree ? 90 : 78;

      out.add(_hint(
        id: 'local_dup_${aId}_$bId',
        treeId: treeId,
        type: 'duplicate',
        title: 'Possible duplicate: ${a['name']}',
        description:
            'Two people share the name "${a['name']}". They may be the same '
            'person — review and merge if so.',
        confidence: confidence,
        personId: aId,
        relatedPersonId: bId,
      ));
    }
  }
  return out;
}

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Map<String, dynamic> _hint({
  required String id,
  required String treeId,
  required String type,
  required String title,
  required String description,
  required int confidence,
  String? personId,
  String? relatedPersonId,
  String? field,
}) =>
    <String, dynamic>{
      'id': id,
      'treeId': treeId,
      'type': type,
      'title': title,
      'description': description,
      'confidence': confidence,
      'status': 'pending',
      'source': 'local',
      'personId': personId,
      'relatedPersonId': relatedPersonId,
      'recordId': null,
      'field': field,
      'suggestedValue': null,
      'relation': null,
      'createdAt': DateTime.now().toIso8601String(),
    };

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../records/domain/entities/record.dart';
import '../../../tree/domain/entities/person.dart';
import '../../domain/entities/hint.dart';

/// The outcome of an AI hint-generation pass.
class AiHintResult {
  const AiHintResult({
    this.hints = const <Hint>[],
    this.available = true,
    this.message,
  });

  final List<Hint> hints;

  /// False when the AI service can't be reached (Supabase not configured, the
  /// `hints` function isn't deployed, or `ANTHROPIC_API_KEY` is unset).
  final bool available;
  final String? message;
}

/// Asks Claude (via the `hints` Supabase Edge Function) for confidence-ranked
/// suggestions about the people in a tree. The API key lives only in the edge
/// function (brief: "keys never on client").
///
/// Degrades gracefully: when the service is unreachable it returns an
/// unavailable result rather than throwing, so the local heuristic isolate can
/// still produce hints.
class HintGenerationService {
  HintGenerationService();

  Future<AiHintResult> generate({
    required String treeId,
    required List<Person> persons,
    required List<Record> records,
  }) async {
    if (!SupabaseConfig.isReady) {
      return const AiHintResult(
        available: false,
        message: 'Connect Supabase to generate AI hints.',
      );
    }
    try {
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'hints',
        body: <String, dynamic>{
          'treeId': treeId,
          'people': persons.map(_personSummary).toList(),
          'records': records.map(_recordSummary).toList(),
        },
      );
      if (res.status != 200) {
        return AiHintResult(
          available: false,
          message: 'Hints service returned ${res.status}.',
        );
      }
      final dynamic data = res.data;
      if (data is Map && data['available'] == false) {
        return AiHintResult(
          available: false,
          message: data['message']?.toString(),
        );
      }
      final List<dynamic> rows = data is Map<String, dynamic>
          ? (data['hints'] as List<dynamic>? ?? const <dynamic>[])
          : (data as List<dynamic>? ?? const <dynamic>[]);
      final List<Hint> hints = rows
          .map((e) => _hintFromAi(
                treeId,
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
      return AiHintResult(hints: hints);
    } on FunctionException catch (e) {
      return AiHintResult(
        available: false,
        message: 'Hints unavailable (${e.status}).',
      );
    } catch (_) {
      return const AiHintResult(
        available: false,
        message: 'Could not reach the hints service.',
      );
    }
  }

  // ── Compact summaries sent to the model ────────────────────────────────────

  Map<String, dynamic> _personSummary(Person p) => <String, dynamic>{
        'id': p.id,
        'name': p.fullName,
        'sex': p.sex.name,
        'birthYear': p.birthDate?.year,
        'deathYear': p.deathDate?.year,
        'birthPlace': p.birthPlace,
        'deathPlace': p.deathPlace,
        'parentIds': p.parentIds,
        'spouseIds': p.spouseIds,
      };

  Map<String, dynamic> _recordSummary(Record r) => <String, dynamic>{
        'id': r.id,
        'type': r.type.name,
        'title': r.title,
        'year': r.year,
        'personIds': r.personIds,
      };

  Hint _hintFromAi(String treeId, Map<String, dynamic> j) {
    final String idStr =
        '${DateTime.now().microsecondsSinceEpoch}_${j['personId'] ?? ''}_${j['type'] ?? ''}';
    return Hint.fromJson(<String, dynamic>{
      'id': j['id'] ?? idStr,
      'treeId': treeId,
      'type': j['type'],
      'title': j['title'],
      'description': j['description'],
      'confidence': j['confidence'],
      'status': 'pending',
      'source': 'ai',
      'personId': j['personId'],
      'relatedPersonId': j['relatedPersonId'],
      'recordId': j['recordId'],
      'field': j['field'],
      'suggestedValue': j['suggestedValue'],
      'relation': j['relation'],
    });
  }
}

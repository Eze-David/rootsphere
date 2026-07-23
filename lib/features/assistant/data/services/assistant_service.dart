import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../records/domain/entities/record.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/domain/entities/timeline_event.dart';
import '../../domain/entities/assistant_result.dart';

/// Client for the `assistant` Supabase Edge Function — eight Claude-powered
/// research capabilities (see the function's header comment for the full
/// list). The API key lives only server-side; this service degrades
/// gracefully (returns `available: false` rather than throwing) whenever
/// Supabase isn't configured, the function isn't reachable, or the server-side
/// cooldown blocks the request (see `assistant_generation_log`).
class AssistantService {
  AssistantService();

  Future<AssistantResponse<String>> summarize({
    required String scope,
    required String text,
  }) {
    return _call<String>(
      action: 'summarize',
      scope: scope,
      body: <String, dynamic>{'text': text},
      parse: (data) => data['summary']?.toString(),
    );
  }

  Future<AssistantResponse<String>> translate({
    required String scope,
    required String text,
    required String targetLanguage,
  }) {
    return _call<String>(
      action: 'translate',
      scope: scope,
      body: <String, dynamic>{'text': text, 'targetLanguage': targetLanguage},
      parse: (data) => data['translation']?.toString(),
    );
  }

  Future<AssistantResponse<List<String>>> identifyLocations({
    required String scope,
    required String text,
  }) {
    return _call<List<String>>(
      action: 'identifyLocations',
      scope: scope,
      body: <String, dynamic>{'text': text},
      parse: (data) => ((data['locations'] as List<dynamic>?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Future<AssistantResponse<String>> transcribeHandwriting({
    required String scope,
    required String fileUrl,
  }) {
    return _call<String>(
      action: 'transcribeHandwriting',
      scope: scope,
      body: <String, dynamic>{'fileUrl': fileUrl},
      parse: (data) => data['text']?.toString(),
    );
  }

  Future<AssistantResponse<List<AncestorSuggestion>>> suggestAncestors({
    required String scope,
    required Person person,
    required List<Person> relatives,
  }) {
    return _call<List<AncestorSuggestion>>(
      action: 'suggestAncestors',
      scope: scope,
      body: <String, dynamic>{
        'person': _personSummary(person),
        'relatives': relatives.map(_personSummary).toList(),
      },
      parse: (data) =>
          ((data['suggestions'] as List<dynamic>?) ?? const <dynamic>[])
              .map((e) => AncestorSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
    );
  }

  Future<AssistantResponse<List<TimelineEntry>>> generateTimeline({
    required String scope,
    required Person person,
    required List<TimelineEvent> events,
    required List<Record> records,
  }) {
    return _call<List<TimelineEntry>>(
      action: 'generateTimeline',
      scope: scope,
      body: <String, dynamic>{
        'person': _personSummary(person),
        'events': events.map((e) => e.toJson()).toList(),
        'records': records.map(_recordSummary).toList(),
      },
      parse: (data) => ((data['entries'] as List<dynamic>?) ?? const <dynamic>[])
          .map((e) => TimelineEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Future<AssistantResponse<List<MissingRecordSuggestion>>> suggestMissingRecords({
    required String scope,
    required Person person,
    required List<RecordType> existingTypes,
  }) {
    return _call<List<MissingRecordSuggestion>>(
      action: 'suggestMissingRecords',
      scope: scope,
      body: <String, dynamic>{
        'person': _personSummary(person),
        'existingRecordTypes': existingTypes.map((t) => t.name).toList(),
      },
      parse: (data) =>
          ((data['suggestions'] as List<dynamic>?) ?? const <dynamic>[])
              .map((e) =>
                  MissingRecordSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
    );
  }

  Future<AssistantResponse<List<ResearchRecommendation>>> researchRecommendations({
    required String scope,
    required Person person,
    required List<Person> relatives,
    required List<Record> records,
  }) {
    return _call<List<ResearchRecommendation>>(
      action: 'researchRecommendations',
      scope: scope,
      body: <String, dynamic>{
        'person': _personSummary(person),
        'relatives': relatives.map(_personSummary).toList(),
        'records': records.map(_recordSummary).toList(),
      },
      parse: (data) =>
          ((data['recommendations'] as List<dynamic>?) ?? const <dynamic>[])
              .map((e) =>
                  ResearchRecommendation.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
    );
  }

  // ── Shared plumbing ─────────────────────────────────────────────────────────

  Future<AssistantResponse<T>> _call<T>({
    required String action,
    required String scope,
    required Map<String, dynamic> body,
    required T? Function(Map<String, dynamic> data) parse,
  }) async {
    if (!SupabaseConfig.isReady) {
      return const AssistantResponse(
        available: false,
        message: 'Connect Supabase to use the AI Assistant.',
      );
    }
    try {
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'assistant',
        body: <String, dynamic>{'action': action, 'scope': scope, ...body},
      );
      if (res.status != 200) {
        return AssistantResponse(
          available: false,
          message: 'Assistant service returned ${res.status}.',
        );
      }
      final dynamic data = res.data;
      if (data is! Map) {
        return const AssistantResponse(
          available: false,
          message: 'Unexpected response from the assistant service.',
        );
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(data);
      if (map['available'] == false) {
        return AssistantResponse(available: false, message: map['message']?.toString());
      }
      return AssistantResponse(available: true, data: parse(map));
    } on FunctionException catch (e) {
      return AssistantResponse(
        available: false,
        message: 'Assistant unavailable (${e.status}).',
      );
    } catch (_) {
      return const AssistantResponse(
        available: false,
        message: 'Could not reach the assistant service.',
      );
    }
  }

  Map<String, dynamic> _personSummary(Person p) => <String, dynamic>{
        'id': p.id,
        'name': p.fullName,
        'sex': p.sex.name,
        'birthYear': p.birthDate?.year,
        'deathYear': p.deathDate?.year,
        'birthPlace': p.birthPlace,
        'deathPlace': p.deathPlace,
      };

  Map<String, dynamic> _recordSummary(Record r) => <String, dynamic>{
        'id': r.id,
        'type': r.type.name,
        'title': r.title,
        'year': r.year,
      };
}

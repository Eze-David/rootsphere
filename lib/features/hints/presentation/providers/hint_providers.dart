import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../../records/domain/entities/record.dart';
import '../../../records/presentation/providers/record_providers.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../data/repositories/hint_repository_local.dart';
import '../../data/repositories/hint_repository_supabase.dart';
import '../../data/services/hint_generation_service.dart';
import '../../data/services/hint_isolate.dart';
import '../../domain/entities/hint.dart';
import '../../domain/repositories/hint_repository.dart';

/// Hint repository: Supabase-backed when configured, local JSON otherwise.
final hintRepositoryProvider = Provider<HintRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return HintRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return HintRepositoryLocal(prefs);
});

/// Claude-backed hint generation (Supabase Edge Function).
final hintGenerationServiceProvider =
    Provider<HintGenerationService>((ref) => HintGenerationService());

/// Streams all hints in the active tree.
final hintsProvider = StreamProvider<List<Hint>>((ref) {
  final repo = ref.watch(hintRepositoryProvider);
  final treeId = ref.watch(activeTreeIdProvider);
  return repo.watchHints(treeId);
});

/// Pending hints only, ranked by confidence (highest first).
final pendingHintsProvider = Provider<List<Hint>>((ref) {
  final List<Hint> all = ref.watch(hintsProvider).value ?? const <Hint>[];
  final List<Hint> pending =
      all.where((h) => h.status == HintStatus.pending).toList();
  pending.sort((a, b) => b.confidence.compareTo(a.confidence));
  return pending;
});

/// Count of pending hints (for the dashboard stat card).
final pendingHintCountProvider = Provider<int>((ref) {
  return ref.watch(pendingHintsProvider).length;
});

/// UI state for hint generation.
class HintsUiState {
  const HintsUiState({this.generating = false, this.message});
  final bool generating;

  /// A non-null note (e.g. "AI offline — showing local suggestions").
  final String? message;

  HintsUiState copyWith({bool? generating, Object? message = _sentinel}) {
    return HintsUiState(
      generating: generating ?? this.generating,
      message: message == _sentinel ? this.message : message as String?,
    );
  }

  static const Object _sentinel = Object();
}

/// Drives hint generation (AI + background-isolate heuristics) and triage
/// (accept → apply the change, dismiss).
class HintController extends Notifier<HintsUiState> {
  @override
  HintsUiState build() => const HintsUiState();

  HintRepository get _repo => ref.read(hintRepositoryProvider);

  /// Regenerates hints: asks Claude (graceful if unavailable) and runs local
  /// heuristics + ranking on a background isolate, then stores the result.
  Future<void> generate() async {
    state = state.copyWith(generating: true, message: null);
    try {
      final String treeId = ref.read(activeTreeIdProvider);
      final List<Person> people =
          ref.read(personsProvider).value ?? const <Person>[];
      final List<Record> records =
          ref.read(recordsProvider).value ?? const <Record>[];

      final AiHintResult ai =
          await ref.read(hintGenerationServiceProvider).generate(
                treeId: treeId,
                persons: people,
                records: records,
              );

      final List<Hint> ranked = await HintProcessor.run(
        treeId: treeId,
        people: people.map(_personSummary).toList(),
        records: records.map(_recordSummary).toList(),
        aiHints: ai.hints,
      );

      await _repo.replacePendingHints(treeId, ranked);

      state = state.copyWith(
        generating: false,
        message: ai.available
            ? null
            : (ai.message ?? 'AI offline — showing local suggestions only.'),
      );
    } catch (e, st) {
      debugPrint('[hints] generate() failed: $e\n$st');
      state = state.copyWith(
        generating: false,
        message: 'Could not generate hints. Please try again.',
      );
    }
  }

  /// Accepts a hint: applies the concrete change when possible, then records
  /// the decision. Returns a short outcome message for the UI.
  Future<String> accept(Hint hint) async {
    String message = 'Hint accepted.';
    if (hint.isApplicable) {
      message = await _apply(hint);
    } else if (hint.type == HintType.duplicate) {
      message = 'Marked for review. Merge duplicates from the tree.';
    }
    await _repo.upsertHint(hint.copyWith(status: HintStatus.accepted));
    return message;
  }

  Future<void> dismiss(Hint hint) async {
    await _repo.upsertHint(hint.copyWith(status: HintStatus.dismissed));
  }

  // ── Apply concrete changes ─────────────────────────────────────────────────

  Future<String> _apply(Hint hint) async {
    final treeRepo = ref.read(treeRepositoryProvider);
    final Map<String, Person> byId = ref.read(personMapProvider);

    switch (hint.type) {
      case HintType.missingData:
        final Person? p = byId[hint.personId];
        if (p == null) return 'Person not found.';
        final Person updated = _applyField(p, hint.field!, hint.suggestedValue!);
        await treeRepo.upsertPerson(updated);
        return 'Updated ${p.fullName}.';

      case HintType.recordMatch:
        final Record? r = ref.read(recordByIdProvider(hint.recordId!));
        if (r == null) return 'Record not found.';
        if (r.personIds.contains(hint.personId)) {
          return 'Already linked.';
        }
        await ref.read(recordRepositoryProvider).upsertRecord(
              r.copyWith(
                personIds: <String>[...r.personIds, hint.personId!],
              ),
            );
        return 'Record linked.';

      case HintType.relationship:
        final String treeId = hint.treeId;
        switch (hint.relation!) {
          case HintRelation.parent:
            await treeRepo.linkChild(
              treeId: treeId,
              parentId: hint.relatedPersonId!,
              childId: hint.personId!,
            );
            break;
          case HintRelation.child:
            await treeRepo.linkChild(
              treeId: treeId,
              parentId: hint.personId!,
              childId: hint.relatedPersonId!,
            );
            break;
          case HintRelation.spouse:
            await treeRepo.linkSpouses(
              treeId: treeId,
              aId: hint.personId!,
              bId: hint.relatedPersonId!,
            );
            break;
        }
        return 'Relationship added.';

      case HintType.duplicate:
        return 'Marked for review.';
    }
  }

  Person _applyField(Person p, String field, String value) {
    switch (field) {
      case 'birthDate':
        return p.copyWith(birthDate: _parseDate(value));
      case 'deathDate':
        return p.copyWith(deathDate: _parseDate(value));
      case 'birthPlace':
        return p.copyWith(birthPlace: value.trim());
      case 'deathPlace':
        return p.copyWith(deathPlace: value.trim());
      case 'religion':
        return p.copyWith(religion: value.trim());
      default:
        return p;
    }
  }

  DateTime? _parseDate(String value) {
    final String v = value.trim();
    final DateTime? parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
    final RegExpMatch? m = RegExp(r'(\d{4})').firstMatch(v);
    if (m != null) return DateTime(int.parse(m.group(1)!));
    return null;
  }

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
}

final hintControllerProvider =
    NotifierProvider<HintController, HintsUiState>(HintController.new);

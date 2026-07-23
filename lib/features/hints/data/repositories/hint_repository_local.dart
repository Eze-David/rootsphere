import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/hint.dart';
import '../../domain/repositories/hint_repository.dart';

/// SharedPreferences-backed [HintRepository] used when Supabase is not
/// configured. Hints are stored as a JSON list keyed by tree id; a broadcast
/// stream per tree lets the UI react to mutations. The demo "okonkwo" tree is
/// seeded once so the Hints screen and dashboard are populated for review.
class HintRepositoryLocal implements HintRepository {
  HintRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;

  final Map<String, StreamController<List<Hint>>> _controllers =
      <String, StreamController<List<Hint>>>{};

  static const String _seededFlag = 'hints_seeded_v1';

  String _key(String treeId) => 'tree_hints_$treeId';

  List<Hint> _read(String treeId) {
    final String? raw = _prefs.getString(_key(treeId));
    if (raw == null || raw.isEmpty) return <Hint>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Hint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Hint>[];
    }
  }

  Future<void> _write(String treeId, List<Hint> hints) async {
    await _prefs.setString(
      _key(treeId),
      jsonEncode(hints.map((h) => h.toJson()).toList()),
    );
    _controllers[treeId]?.add(hints);
  }

  @override
  Stream<List<Hint>> watchHints(String treeId) {
    _maybeSeed(treeId);
    final controller = _controllers.putIfAbsent(
      treeId,
      () => StreamController<List<Hint>>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(_read(treeId)));
    return controller.stream;
  }

  @override
  Future<List<Hint>> getHints(String treeId) async {
    _maybeSeed(treeId);
    return _read(treeId);
  }

  @override
  Future<void> upsertHint(Hint hint) async {
    final List<Hint> hints = _read(hint.treeId);
    final int idx = hints.indexWhere((h) => h.id == hint.id);
    if (idx >= 0) {
      hints[idx] = hint;
    } else {
      hints.add(hint);
    }
    await _write(hint.treeId, hints);
  }

  @override
  Future<void> replacePendingHints(String treeId, List<Hint> hints) async {
    // Keep the user's already-triaged hints; drop old pending ones.
    final List<Hint> kept = _read(treeId)
        .where((h) => h.status != HintStatus.pending)
        .toList();
    final Set<String> keptKeys = kept.map(_dedupeKey).toSet();
    // Avoid resurfacing a hint the user already accepted/dismissed.
    final List<Hint> fresh =
        hints.where((h) => !keptKeys.contains(_dedupeKey(h))).toList();
    await _write(treeId, <Hint>[...kept, ...fresh]);
  }

  /// A stable identity for a hint independent of its random id, so a freshly
  /// generated hint matching a dismissed one isn't shown again.
  String _dedupeKey(Hint h) => <String>[
        h.type.name,
        h.personId ?? '',
        h.relatedPersonId ?? '',
        h.recordId ?? '',
        h.field ?? '',
      ].join('|');

  @override
  Future<void> deleteHint(String treeId, String id) async {
    final List<Hint> hints = _read(treeId)..removeWhere((h) => h.id == id);
    await _write(treeId, hints);
  }

  // ── Seed ───────────────────────────────────────────────────────────────────

  void _maybeSeed(String treeId) {
    if (treeId != 'okonkwo') return;
    if (_prefs.getBool(_seededFlag) == true) return;
    if (_read(treeId).isNotEmpty) return;

    const String tree = 'okonkwo';
    final DateTime now = DateTime.now();

    final List<Hint> seed = <Hint>[
      Hint(
        id: 'hint_seed_record_ngozi',
        treeId: tree,
        type: HintType.recordMatch,
        title: '1901 census match · Ngozi',
        description:
            'A 1901 census entry may correspond to Ngozi. Review and link it '
            'to her profile.',
        confidence: 88,
        source: 'local',
        personId: 'ngozi',
        createdAt: now,
      ),
      Hint(
        id: 'hint_seed_missing_emeka',
        treeId: tree,
        type: HintType.missingData,
        title: 'Add a death date for Emeka',
        description:
            'Emeka has no death date recorded. Adding one improves timeline '
            'accuracy and record matching.',
        confidence: 72,
        source: 'local',
        personId: 'emeka',
        field: 'deathDate',
        createdAt: now,
      ),
      Hint(
        id: 'hint_seed_missing_adaeze',
        treeId: tree,
        type: HintType.missingData,
        title: 'Add a birthplace for Adaeze',
        description:
            'Adaeze has no birthplace. Knowing where she was born helps surface '
            'local records.',
        confidence: 60,
        source: 'local',
        personId: 'adaeze',
        field: 'birthPlace',
        createdAt: now,
      ),
    ];

    _prefs.setString(
      _key(tree),
      jsonEncode(seed.map((h) => h.toJson()).toList()),
    );
    _prefs.setBool(_seededFlag, true);
  }
}

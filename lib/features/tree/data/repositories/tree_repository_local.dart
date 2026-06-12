import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/person.dart';
import '../../domain/repositories/tree_repository.dart';

/// SharedPreferences-backed [TreeRepository].
///
/// Persons are stored as a JSON list keyed by tree id. A broadcast stream per
/// tree lets the UI react to mutations. Replace with a Supabase implementation
/// in a later phase — the interface stays the same.
class TreeRepositoryLocal implements TreeRepository {
  TreeRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;

  final Map<String, StreamController<List<Person>>> _controllers =
      <String, StreamController<List<Person>>>{};

  static const String _seededFlag = 'tree_seeded_v1';

  String _key(String treeId) => 'tree_persons_$treeId';

  // ── Reads ────────────────────────────────────────────────────────────────

  List<Person> _read(String treeId) {
    final String? raw = _prefs.getString(_key(treeId));
    if (raw == null || raw.isEmpty) return <Person>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Person.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Person>[];
    }
  }

  Future<void> _write(String treeId, List<Person> persons) async {
    final String encoded = jsonEncode(persons.map((p) => p.toJson()).toList());
    await _prefs.setString(_key(treeId), encoded);
    _controllers[treeId]?.add(persons);
  }

  @override
  Future<List<Person>> getPersons(String treeId) async {
    _maybeSeed(treeId);
    return _read(treeId);
  }

  @override
  Stream<List<Person>> watchPersons(String treeId) {
    _maybeSeed(treeId);
    final controller = _controllers.putIfAbsent(
      treeId,
      () => StreamController<List<Person>>.broadcast(),
    );
    // Emit the current value to new listeners on the next microtask.
    scheduleMicrotask(() => controller.add(_read(treeId)));
    return controller.stream;
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  @override
  Future<void> upsertPerson(Person person) async {
    final List<Person> persons = _read(person.treeId);
    final int idx = persons.indexWhere((p) => p.id == person.id);
    if (idx >= 0) {
      persons[idx] = person;
    } else {
      persons.add(person);
    }
    await _write(person.treeId, persons);
  }

  @override
  Future<void> deletePerson(String treeId, String id) async {
    final List<Person> persons = _read(treeId);
    persons.removeWhere((p) => p.id == id);
    // Scrub dangling references.
    for (int i = 0; i < persons.length; i++) {
      final Person p = persons[i];
      if (p.parentIds.contains(id) || p.spouseIds.contains(id)) {
        persons[i] = p.copyWith(
          parentIds: p.parentIds.where((x) => x != id).toList(),
          spouseIds: p.spouseIds.where((x) => x != id).toList(),
        );
      }
    }
    await _write(treeId, persons);
  }

  @override
  Future<void> linkChild({
    required String treeId,
    required String parentId,
    required String childId,
  }) async {
    final List<Person> persons = _read(treeId);
    final int idx = persons.indexWhere((p) => p.id == childId);
    if (idx < 0) return;
    final Person child = persons[idx];
    if (!child.parentIds.contains(parentId)) {
      persons[idx] = child.copyWith(
        parentIds: <String>[...child.parentIds, parentId],
      );
      await _write(treeId, persons);
    }
  }

  @override
  Future<void> linkSpouses({
    required String treeId,
    required String aId,
    required String bId,
  }) async {
    final List<Person> persons = _read(treeId);
    void addSpouse(String fromId, String toId) {
      final int idx = persons.indexWhere((p) => p.id == fromId);
      if (idx < 0) return;
      final Person p = persons[idx];
      if (!p.spouseIds.contains(toId)) {
        persons[idx] = p.copyWith(spouseIds: <String>[...p.spouseIds, toId]);
      }
    }

    addSpouse(aId, bId);
    addSpouse(bId, aId);
    await _write(treeId, persons);
  }

  // ── Seed ───────────────────────────────────────────────────────────────────

  /// Seeds the demo "Okonkwo" tree from the Phase 2 mockup on first launch.
  void _maybeSeed(String treeId) {
    if (treeId != 'okonkwo') return;
    if (_prefs.getBool(_seededFlag) == true) return;
    if (_read(treeId).isNotEmpty) return;

    DateTime y(int year) => DateTime(year, 1, 1);
    const String tree = 'okonkwo';

    final List<Person> seed = <Person>[
      Person(
        id: 'arthur',
        treeId: tree,
        givenName: 'Arthur',
        surname: 'O.',
        sex: Sex.male,
        birthDate: y(1918),
        deathDate: y(1989),
        spouseIds: const <String>['grace'],
      ),
      Person(
        id: 'grace',
        treeId: tree,
        givenName: 'Grace',
        surname: 'N.',
        sex: Sex.female,
        birthDate: y(1922),
        deathDate: y(2001),
        spouseIds: const <String>['arthur'],
      ),
      Person(
        id: 'emeka',
        treeId: tree,
        givenName: 'Emeka',
        surname: 'O.',
        sex: Sex.male,
        birthDate: y(1950),
        parentIds: const <String>['arthur', 'grace'],
        spouseIds: const <String>['ngozi'],
      ),
      Person(
        id: 'ngozi',
        treeId: tree,
        givenName: 'Ngozi',
        surname: 'A.',
        sex: Sex.female,
        birthDate: y(1953),
        spouseIds: const <String>['emeka'],
      ),
      Person(
        id: 'adaeze',
        treeId: tree,
        givenName: 'Adaeze',
        surname: 'O.',
        sex: Sex.female,
        birthDate: y(1986),
        parentIds: const <String>['emeka', 'ngozi'],
      ),
    ];

    final String encoded = jsonEncode(seed.map((p) => p.toJson()).toList());
    _prefs.setString(_key(tree), encoded);
    _prefs.setBool(_seededFlag, true);
  }
}

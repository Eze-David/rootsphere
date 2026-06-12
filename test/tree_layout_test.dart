import 'package:flutter_test/flutter_test.dart';
import 'package:rootsphere/features/tree/domain/entities/person.dart';
import 'package:rootsphere/features/tree/presentation/layout/tree_layout.dart';

void main() {
  // The seed tree from the Phase 2 mockup: Arthur+Grace -> Emeka+Ngozi -> Adaeze.
  final persons = <Person>[
    const Person(
      id: 'arthur',
      treeId: 't',
      givenName: 'Arthur',
      spouseIds: <String>['grace'],
    ),
    const Person(
      id: 'grace',
      treeId: 't',
      givenName: 'Grace',
      spouseIds: <String>['arthur'],
    ),
    const Person(
      id: 'emeka',
      treeId: 't',
      givenName: 'Emeka',
      parentIds: <String>['arthur', 'grace'],
      spouseIds: <String>['ngozi'],
    ),
    const Person(
      id: 'ngozi',
      treeId: 't',
      givenName: 'Ngozi',
      spouseIds: <String>['emeka'],
    ),
    const Person(
      id: 'adaeze',
      treeId: 't',
      givenName: 'Adaeze',
      parentIds: <String>['emeka', 'ngozi'],
    ),
  ];

  group('TreeLayoutEngine', () {
    test('descendants from root places all reachable people', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'arthur',
        mode: TreeMode.descendants,
      );
      final ids = layout.nodes.map((n) => n.person.id).toSet();
      expect(ids, containsAll(<String>['arthur', 'grace', 'emeka', 'ngozi', 'adaeze']));
      expect(layout.generations, 3);
      expect(layout.size.width, greaterThan(0));
      expect(layout.size.height, greaterThan(0));
    });

    test('focus node is flagged and within bounds', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'adaeze',
        mode: TreeMode.ancestors,
      );
      final focus = layout.nodes.firstWhere((n) => n.isFocus);
      expect(focus.person.id, 'adaeze');
      expect(layout.focusRect, focus.rect);
    });

    test('ancestors from leaf reaches grandparents', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'adaeze',
        mode: TreeMode.ancestors,
      );
      final ids = layout.nodes.map((n) => n.person.id).toSet();
      expect(ids, containsAll(<String>['adaeze', 'emeka', 'ngozi', 'arthur', 'grace']));
    });

    test('cards do not overlap each other', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'arthur',
        mode: TreeMode.descendants,
      );
      for (int i = 0; i < layout.nodes.length; i++) {
        for (int j = i + 1; j < layout.nodes.length; j++) {
          final a = layout.nodes[i].rect;
          final b = layout.nodes[j].rect;
          // Allow touching edges but not real overlap.
          final overlap = a.overlaps(b.deflate(0.5));
          expect(overlap, isFalse,
              reason: '${layout.nodes[i].person.id} overlaps '
                  '${layout.nodes[j].person.id}');
        }
      }
    });

    test('pedigree includes ancestors and descendants of focus', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'emeka',
        mode: TreeMode.pedigree,
      );
      final ids = layout.nodes.map((n) => n.person.id).toSet();
      // Parents (up) and child (down) of Emeka.
      expect(ids, containsAll(<String>['arthur', 'grace', 'emeka', 'adaeze']));
    });
  });
}

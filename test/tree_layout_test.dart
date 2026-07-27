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

    test('ancestors (kinship) adds Add-parent slots and captions', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'adaeze',
        mode: TreeMode.ancestors,
      );
      // ngozi, arthur and grace have unknown parents → placeholder slots.
      expect(layout.slots, isNotEmpty);
      expect(
        layout.slots.every((s) => s.label.startsWith('Add ')),
        isTrue,
      );
      // Captions are generated per generation relative to the focus.
      final captions = layout.labels.map((l) => l.text).toList();
      expect(captions, contains("Adaeze's parents"));
      expect(captions, contains("Adaeze's grandparents"));
      // Each real person gets a collapse toggle.
      expect(layout.toggles.map((t) => t.personId), contains('adaeze'));
    });

    test('horizontal orientation grows ancestors to the right of focus', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'adaeze',
        mode: TreeMode.ancestors,
        orientation: TreeOrientation.horizontal,
      );
      final focus = layout.nodes.firstWhere((n) => n.isFocus);
      // Every other node (real or parent) sits to the right of the focus.
      for (final n in layout.nodes.where((n) => !n.isFocus)) {
        expect(n.rect.left, greaterThan(focus.rect.left));
      }
      for (final s in layout.slots) {
        expect(s.rect.left, greaterThan(focus.rect.left));
      }
    });

    test('collapsing a person hides its ancestors', () {
      final full = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'adaeze',
        mode: TreeMode.ancestors,
      );
      final collapsed = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'adaeze',
        mode: TreeMode.ancestors,
        collapsed: <String>{'adaeze'},
      );
      // Collapsing the focus removes all ancestors and slots above it.
      expect(collapsed.nodes.length, lessThan(full.nodes.length));
      expect(collapsed.nodes.map((n) => n.person.id), <String>['adaeze']);
      expect(collapsed.slots, isEmpty);
    });

    test('descendants places a spouse beside the person, connects children '
        'below and captions each generation', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'arthur',
        mode: TreeMode.descendants,
      );

      // Grace (spouse) sits on the same row as Arthur.
      final arthur = layout.nodes.firstWhere((n) => n.person.id == 'arthur');
      final grace = layout.nodes.firstWhere((n) => n.person.id == 'grace');
      expect(grace.rect.top, arthur.rect.top);
      expect(grace.rect.left, greaterThan(arthur.rect.left));

      // Captions are generated per generation relative to the focus.
      final captions = layout.labels.map((l) => l.text).toList();
      expect(captions, contains("Arthur's children"));
      expect(captions, contains("Arthur's grandchildren"));

      // Arthur and Emeka both have children, so each gets a collapse toggle.
      final toggleIds = layout.toggles.map((t) => t.personId).toSet();
      expect(toggleIds, containsAll(<String>['arthur', 'emeka']));
      // Ngozi and Adaeze have no children of their own — no toggle for them.
      expect(toggleIds, isNot(contains('ngozi')));
      expect(toggleIds, isNot(contains('adaeze')));
    });

    test('collapsing a person hides its descendants but keeps their toggle', () {
      final collapsed = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'arthur',
        mode: TreeMode.descendants,
        collapsed: <String>{'emeka'},
      );
      final ids = collapsed.nodes.map((n) => n.person.id).toSet();
      expect(ids, containsAll(<String>['arthur', 'grace', 'emeka', 'ngozi']));
      expect(ids, isNot(contains('adaeze')));

      final emekaToggle =
          collapsed.toggles.firstWhere((t) => t.personId == 'emeka');
      expect(emekaToggle.collapsed, isTrue);
    });

    test('ancestors pedigree also shows the focus\'s spouse beside them and '
        'children below, alongside the ancestors above', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'emeka',
        mode: TreeMode.ancestors,
      );
      final ids = layout.nodes.map((n) => n.person.id).toSet();
      // Ancestors (arthur, grace) and the focus's own spouse + child are all
      // present in a single view.
      expect(
        ids,
        containsAll(<String>['emeka', 'arthur', 'grace', 'ngozi', 'adaeze']),
      );

      final emeka = layout.nodes.firstWhere((n) => n.person.id == 'emeka');
      final ngozi = layout.nodes.firstWhere((n) => n.person.id == 'ngozi');
      final adaeze = layout.nodes.firstWhere((n) => n.person.id == 'adaeze');
      final arthur = layout.nodes.firstWhere((n) => n.person.id == 'arthur');

      // Spouse sits beside the focus, same row.
      expect(ngozi.rect.top, emeka.rect.top);
      expect(ngozi.rect.left, greaterThan(emeka.rect.left));
      // Child sits below the couple.
      expect(adaeze.rect.top, greaterThan(emeka.rect.bottom));
      // The gap down to the children row is deliberately more generous than
      // the gap up to the ancestor generations, so it doesn't feel cramped
      // against the focus card.
      final double childGap = adaeze.rect.top - emeka.rect.bottom;
      final double ancestorGap = emeka.rect.top - arthur.rect.bottom;
      expect(childGap, greaterThan(ancestorGap));

      // Both an ancestors caption and a children caption are present.
      final captions = layout.labels.map((l) => l.text).toList();
      expect(captions, contains("Emeka's parents"));
      expect(captions, contains("Emeka's children"));

      // The child's connector starts at the couple's row-centre height (where
      // the spouse connector sits) and is horizontally centred between them —
      // not offset toward Emeka's own card — so there's no visible gap where
      // the two lines should meet.
      final childConnector = layout.connectors.firstWhere(
        (c) => !c.isSpouse && c.points.last == Offset(adaeze.rect.center.dx, adaeze.rect.top),
      );
      final Offset start = childConnector.points.first;
      expect(start.dy, emeka.rect.center.dy);
      expect(start.dx, (emeka.rect.center.dx + ngozi.rect.center.dx) / 2);

      // A children-toggle exists for the focus, namespaced apart from any
      // ancestor-collapse toggle so the two don't interfere.
      final toggleIds = layout.toggles.map((t) => t.personId).toSet();
      expect(toggleIds, contains('emeka')); // ancestor-collapse toggle
      expect(toggleIds, contains('children:emeka')); // children-collapse toggle

      // Nothing overlaps, including the new spouse/child cards.
      for (int i = 0; i < layout.nodes.length; i++) {
        for (int j = i + 1; j < layout.nodes.length; j++) {
          final a = layout.nodes[i].rect;
          final b = layout.nodes[j].rect;
          expect(a.overlaps(b.deflate(0.5)), isFalse,
              reason: '${layout.nodes[i].person.id} overlaps '
                  '${layout.nodes[j].person.id}');
        }
      }
    });

    test('collapsing the focus\'s children hides them but keeps their toggle', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'emeka',
        mode: TreeMode.ancestors,
        collapsed: <String>{'children:emeka'},
      );
      final ids = layout.nodes.map((n) => n.person.id).toSet();
      expect(ids, contains('ngozi')); // spouse still shown
      expect(ids, isNot(contains('adaeze'))); // child hidden

      final toggle =
          layout.toggles.firstWhere((t) => t.personId == 'children:emeka');
      expect(toggle.collapsed, isTrue);
    });

    test('horizontal: child connector meets the spouse connector with no gap', () {
      final layout = TreeLayoutEngine.build(
        persons: persons,
        focusId: 'emeka',
        mode: TreeMode.ancestors,
        orientation: TreeOrientation.horizontal,
      );
      final emeka = layout.nodes.firstWhere((n) => n.person.id == 'emeka');
      final ngozi = layout.nodes.firstWhere((n) => n.person.id == 'ngozi');
      final adaeze = layout.nodes.firstWhere((n) => n.person.id == 'adaeze');

      // In horizontal mode the spouse stacks below the focus (breadth runs
      // vertically), and their connector is drawn at the shared column's
      // horizontal centre, not its edge.
      expect(ngozi.rect.left, emeka.rect.left);
      expect(ngozi.rect.top, greaterThan(emeka.rect.bottom));

      final childConnector = layout.connectors.firstWhere(
        (c) => !c.isSpouse && c.points.last == Offset(adaeze.rect.right, adaeze.rect.center.dy),
      );
      final Offset start = childConnector.points.first;
      expect(start.dx, emeka.rect.center.dx);
      expect(start.dy, (emeka.rect.center.dy + ngozi.rect.center.dy) / 2);
    });

    test(
      'a couple stays as tight as the focus\'s own spouse gap even when one '
      'side has far more recorded ancestors than the other',
      () {
        // Arthur has two more known generations behind him; Grace has none —
        // a deliberately asymmetric subtree, same shape as a real user's tree
        // (one parent's line is well documented, the other isn't).
        final asymmetric = <Person>[
          ...persons,
          const Person(
            id: 'arthur_dad',
            treeId: 't',
            givenName: 'ArthurDad',
            spouseIds: <String>['arthur_mom'],
          ),
          const Person(
            id: 'arthur_mom',
            treeId: 't',
            givenName: 'ArthurMom',
            spouseIds: <String>['arthur_dad'],
          ),
          const Person(
            id: 'arthur_gdad',
            treeId: 't',
            givenName: 'ArthurGDad',
            spouseIds: <String>['arthur_gmom'],
          ),
          const Person(
            id: 'arthur_gmom',
            treeId: 't',
            givenName: 'ArthurGMom',
            spouseIds: <String>['arthur_gdad'],
          ),
        ];
        final withDeepArthurLine = <Person>[
          for (final p in asymmetric)
            if (p.id == 'arthur')
              Person(
                id: p.id,
                treeId: p.treeId,
                givenName: p.givenName,
                spouseIds: p.spouseIds,
                parentIds: const <String>['arthur_dad', 'arthur_mom'],
              )
            else if (p.id == 'arthur_dad')
              Person(
                id: p.id,
                treeId: p.treeId,
                givenName: p.givenName,
                spouseIds: p.spouseIds,
                parentIds: const <String>['arthur_gdad', 'arthur_gmom'],
              )
            else
              p,
        ];

        final layout = TreeLayoutEngine.build(
          persons: withDeepArthurLine,
          focusId: 'emeka',
          mode: TreeMode.ancestors,
        );
        final arthur = layout.nodes.firstWhere((n) => n.person.id == 'arthur');
        final grace = layout.nodes.firstWhere((n) => n.person.id == 'grace');
        final emeka = layout.nodes.firstWhere((n) => n.person.id == 'emeka');
        final ngozi = layout.nodes.firstWhere((n) => n.person.id == 'ngozi');

        // Arthur+Grace (a couple with lopsided ancestry) sit exactly as
        // tight as Emeka+Ngozi (the focus's own spouse pairing).
        final double ancestorCoupleGap = grace.rect.left - arthur.rect.right;
        final double focusCoupleGap = ngozi.rect.left - emeka.rect.right;
        expect(ancestorCoupleGap, closeTo(focusCoupleGap, 0.01));
        expect(ancestorCoupleGap, closeTo(TreeMetrics.spouseGap, 0.01));

        // Nothing overlaps despite Arthur's much wider subtree.
        for (int i = 0; i < layout.nodes.length; i++) {
          for (int j = i + 1; j < layout.nodes.length; j++) {
            final a = layout.nodes[i].rect;
            final b = layout.nodes[j].rect;
            expect(
              a.overlaps(b.deflate(0.5)),
              isFalse,
              reason: '${layout.nodes[i].person.id} overlaps '
                  '${layout.nodes[j].person.id}',
            );
          }
        }
      },
    );

    test(
      'the male half of the focus\'s couple always ends up first along the '
      'breadth axis, whichever of the two is currently the focus',
      () {
        final withSexes = <Person>[
          const Person(
            id: 'drcar',
            treeId: 't',
            givenName: 'DrCar',
            sex: Sex.male,
            spouseIds: <String>['venza'],
          ),
          const Person(
            id: 'venza',
            treeId: 't',
            givenName: 'Venza',
            sex: Sex.female,
            spouseIds: <String>['drcar'],
          ),
        ];

        final rootedOnMale = TreeLayoutEngine.build(
          persons: withSexes,
          focusId: 'drcar',
          mode: TreeMode.ancestors,
        );
        final rootedOnFemale = TreeLayoutEngine.build(
          persons: withSexes,
          focusId: 'venza',
          mode: TreeMode.ancestors,
        );

        for (final layout in <TreeLayout>[rootedOnMale, rootedOnFemale]) {
          final male = layout.nodes.firstWhere((n) => n.person.id == 'drcar');
          final female = layout.nodes.firstWhere(
            (n) => n.person.id == 'venza',
          );
          expect(
            male.rect.left,
            lessThan(female.rect.left),
            reason:
                'male should be left of female regardless of who is focus '
                '(focus here: ${layout.nodes.firstWhere((n) => n.isFocus).person.id})',
          );
        }
      },
    );
  });
}

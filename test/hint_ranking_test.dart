import 'package:flutter_test/flutter_test.dart';
import 'package:rootsphere/features/hints/data/services/hint_isolate.dart';

void main() {
  group('rankHintsIsolate', () {
    test('flags missing birth data and ranks by confidence', () {
      final result = rankHintsIsolate(<String, dynamic>{
        'treeId': 't1',
        'people': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p1',
            'name': 'Ada Okafor',
            'birthYear': null,
            'birthPlace': null,
            'spouseIds': <String>['p2'],
            'parentIds': <String>[],
          },
        ],
        'records': <Map<String, dynamic>>[],
        'aiHints': <Map<String, dynamic>>[],
      });

      // Missing birth date (higher confidence) should rank above birthplace.
      expect(result.length, 2);
      expect(result.first['field'], 'birthDate');
      expect(result.last['field'], 'birthPlace');
      expect(
        result.first['confidence'] as int,
        greaterThanOrEqualTo(result.last['confidence'] as int),
      );
    });

    test('detects duplicates by normalised name', () {
      final result = rankHintsIsolate(<String, dynamic>{
        'treeId': 't1',
        'people': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p1',
            'name': 'John Bello',
            'birthYear': 1900,
            'birthPlace': 'Lagos',
          },
          <String, dynamic>{
            'id': 'p2',
            'name': 'john  bello',
            'birthYear': 1900,
            'birthPlace': 'Lagos',
          },
        ],
        'records': <Map<String, dynamic>>[],
        'aiHints': <Map<String, dynamic>>[],
      });

      final dup = result.where((h) => h['type'] == 'duplicate').toList();
      expect(dup.length, 1);
      // Agreeing birth years => high confidence.
      expect(dup.first['confidence'] as int, greaterThanOrEqualTo(85));
    });

    test('de-duplicates AI and local hints, AI taking precedence', () {
      final result = rankHintsIsolate(<String, dynamic>{
        'treeId': 't1',
        'people': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p1',
            'name': 'Ada Okafor',
            'birthYear': null,
            'birthPlace': 'Enugu',
          },
        ],
        'records': <Map<String, dynamic>>[],
        'aiHints': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'ai1',
            'treeId': 't1',
            'type': 'missingData',
            'title': 'AI: add birth date',
            'description': 'inferred',
            'confidence': 95,
            'status': 'pending',
            'source': 'ai',
            'personId': 'p1',
            'field': 'birthDate',
            'suggestedValue': '1901',
          },
        ],
      });

      // Only one missingData/birthDate hint for p1 — the AI one wins.
      final birth = result
          .where((h) => h['type'] == 'missingData' && h['field'] == 'birthDate')
          .toList();
      expect(birth.length, 1);
      expect(birth.first['source'], 'ai');
      expect(birth.first['suggestedValue'], '1901');
    });
  });
}

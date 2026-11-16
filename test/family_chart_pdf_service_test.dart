import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rootsphere/features/records/domain/entities/record.dart';
import 'package:rootsphere/features/tree/data/services/family_chart_pdf_service.dart';
import 'package:rootsphere/features/tree/domain/entities/person.dart';

/// A focus person with [generations] full generations of ancestors, two
/// spouses and children split between them.
Map<String, Person> _tree({int generations = 4}) {
  final Map<String, Person> people = <String, Person>{};
  List<String> addAncestors(String childKey, int depth) {
    if (depth > generations) return const <String>[];
    final List<String> ids = <String>[];
    for (final Sex sex in <Sex>[Sex.male, Sex.female]) {
      final String id = '$childKey${sex == Sex.male ? 'f' : 'm'}';
      people[id] = Person(
        id: id,
        treeId: 't',
        givenName: sex == Sex.male ? 'Chukwuemeka' : 'Adaeze',
        surname: 'Okonkwo $depth',
        sex: sex,
        birthDate: DateTime(1990 - depth * 28, 3, 12),
        deathDate: depth > 1 ? DateTime(2060 - depth * 28) : null,
        birthPlace: 'Enugu, Nigeria',
        parentIds: addAncestors(id, depth + 1),
      );
      ids.add(id);
    }
    return ids;
  }

  people['p'] = Person(
    id: 'p',
    treeId: 't',
    givenName: 'Mary',
    surname: 'Deo',
    sex: Sex.female,
    birthDate: DateTime(1990, 5, 1),
    birthPlace: 'Lagos, Nigeria',
    parentIds: addAncestors('p', 1),
    spouseIds: const <String>['s1', 's2'],
  );
  for (final String id in <String>['s1', 's2']) {
    people[id] = Person(
      id: id,
      treeId: 't',
      givenName: 'Spouse',
      surname: id,
      sex: Sex.male,
      spouseIds: const <String>['p'],
    );
  }
  for (int i = 0; i < 5; i++) {
    people['c$i'] = Person(
      id: 'c$i',
      treeId: 't',
      givenName: 'Child',
      surname: '$i',
      birthDate: DateTime(2012 + i),
      parentIds: <String>['p', if (i < 3) 's1' else if (i < 4) 's2'],
    );
  }
  return people;
}

void main() {
  final ChartFonts fonts = ChartFonts(
    body: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    display: pw.Font.timesBold(),
  );
  final List<Record> records = <Record>[
    Record(
      id: 'r1',
      treeId: 't',
      type: RecordType.birth,
      title: 'Birth certificate of Mary Deo',
      repository: 'National Population Commission',
      personIds: const <String>['p'],
    ),
  ];

  for (final PersonPrintKind kind in PersonPrintKind.values) {
    if (kind == PersonPrintKind.personDetails) continue;

    test('${kind.name} renders for a full tree', () async {
      final Map<String, Person> people = _tree();
      final Uint8List bytes = await FamilyChartPdfService.build(
        kind: kind,
        person: people['p']!,
        people: people,
        records: records,
        format: PdfPageFormat.a4,
        fonts: fonts,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final String? out = Platform.environment['CHART_PDF_OUT'];
      if (out != null) File('$out/${kind.name}.pdf').writeAsBytesSync(bytes);
    });

    test('${kind.name} renders for a person with no relatives', () async {
      const Person loner = Person(id: 'x', treeId: 't', givenName: 'Solo');
      final Uint8List bytes = await FamilyChartPdfService.build(
        kind: kind,
        person: loner,
        people: const <String, Person>{'x': loner},
        format: PdfPageFormat.a4,
        fonts: fonts,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  }
}

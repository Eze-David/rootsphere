import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../records/domain/entities/record.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/timeline_event.dart';

/// The printable documents offered by a profile's "Print options" dialog.
enum PersonPrintKind {
  personDetails,
  pedigree,
  portraitPedigree,
  fanChart,
  familyGroupRecord,
  familyGroupRecordWithSources,
}

/// The fonts every chart is drawn with. Loaded from Google Fonts by
/// [FamilyChartPdfService.build]; injectable so tests can render without a
/// network connection.
class ChartFonts {
  const ChartFonts({
    required this.body,
    required this.bold,
    required this.display,
    this.fallback = const <pw.Font>[],
  });

  final pw.Font body;
  final pw.Font bold;
  final pw.Font display;

  /// Covers the dotted-Latin letters of Yoruba/Igbo orthography that the
  /// main fonts lack (see `TreePdfService`).
  final List<pw.Font> fallback;

  static Future<ChartFonts> load() async => ChartFonts(
    body: await PdfGoogleFonts.dMSansRegular(),
    bold: await PdfGoogleFonts.dMSansBold(),
    display: await PdfGoogleFonts.playfairDisplayBold(),
    fallback: <pw.Font>[await PdfGoogleFonts.notoSansRegular()],
  );
}

/// Renders the family-centred print options for one person: a numbered
/// pedigree chart form, a portrait pedigree (with photos), a fan chart, and a family
/// group record (optionally with each member's attached sources).
///
/// The single-person "Person Details" sheet lives in `PersonPdfService`.
class FamilyChartPdfService {
  FamilyChartPdfService._();

  static const PdfColor _male = PdfColor.fromInt(0xFF6E86A6);
  static const PdfColor _female = PdfColor.fromInt(0xFFC76A4D);
  static const PdfColor _neutral = PdfColor.fromInt(0xFF9A938B);
  static const PdfColor _maleFill = PdfColor.fromInt(0xFFDCE4EE);
  static const PdfColor _femaleFill = PdfColor.fromInt(0xFFF3DDD5);
  static const PdfColor _neutralFill = PdfColor.fromInt(0xFFECE9E5);
  static const PdfColor _emptyFill = PdfColor.fromInt(0xFFF7F5F2);
  static const PdfColor _ink = PdfColor.fromInt(0xFF1C1917);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B6660);
  static const PdfColor _line = PdfColor.fromInt(0xFF9C968E);
  static const PdfColor _white = PdfColor.fromInt(0xFFFFFFFF);

  static const double _margin = 28;
  static const double _headerH = 44;

  /// Whether [kind] reads best on a landscape page.
  static bool isLandscape(PersonPrintKind kind) =>
      kind == PersonPrintKind.fanChart;

  /// Builds the PDF for any [kind] except [PersonPrintKind.personDetails].
  ///
  /// [people] is every person in the tree keyed by id; [records] is every
  /// record in the tree (only used by the "with sources" group record).
  static Future<Uint8List> build({
    required PersonPrintKind kind,
    required Person person,
    required Map<String, Person> people,
    required PdfPageFormat format,
    List<Record> records = const <Record>[],
    ChartFonts? fonts,
  }) async {
    final ChartFonts f = fonts ?? await ChartFonts.load();
    final pw.Document doc = pw.Document();
    switch (kind) {
      case PersonPrintKind.personDetails:
        throw ArgumentError('Person details are built by PersonPdfService.');
      case PersonPrintKind.pedigree:
        doc.addPage(_pedigreePage(person, people, f, format));
      case PersonPrintKind.portraitPedigree:
        final _PortraitData data = _PortraitData.of(person, people);
        final Map<String, pw.ImageProvider> photos = await _loadPhotos(
          data.everyone,
        );
        doc.addPage(_portraitPage(data, photos, f, format));
      case PersonPrintKind.fanChart:
        doc.addPage(_fanPage(person, people, f, format));
      case PersonPrintKind.familyGroupRecord:
      case PersonPrintKind.familyGroupRecordWithSources:
        doc.addPage(
          _groupRecordPage(
            person,
            people,
            f,
            format,
            records: kind == PersonPrintKind.familyGroupRecordWithSources
                ? records
                : null,
          ),
        );
    }
    return doc.save();
  }

  // ---------------------------------------------------------------- shared

  static pw.TextStyle _ts(
    ChartFonts f,
    double size, {
    bool bold = false,
    PdfColor color = _ink,
  }) => pw.TextStyle(
    font: bold ? f.bold : f.body,
    fontFallback: f.fallback,
    fontSize: size,
    color: color,
  );

  static pw.Widget _header(ChartFonts f, String title, String subtitle) =>
      pw.SizedBox(
        height: _headerH,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    title,
                    maxLines: 1,
                    style: pw.TextStyle(
                      font: f.display,
                      fontFallback: f.fallback,
                      fontSize: 18,
                      color: _ink,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    subtitle,
                    maxLines: 1,
                    style: _ts(f, 9, color: _muted),
                  ),
                ],
              ),
            ),
            pw.Text(
              'Rootsphere · ${Person.fmtDate(DateTime.now())}',
              style: _ts(f, 8, color: _muted),
            ),
          ],
        ),
      );

  static PdfColor _tint(Sex sex) => switch (sex) {
    Sex.male => _male,
    Sex.female => _female,
    Sex.unknown => _neutral,
  };

  static PdfColor _fill(Sex sex) => switch (sex) {
    Sex.male => _maleFill,
    Sex.female => _femaleFill,
    Sex.unknown => _neutralFill,
  };

  /// "1950–2010", "1992–Living", "Deceased" … empty when nothing is known.
  static String _years(Person p) {
    final int? b = p.birthDate?.year;
    final int? d = p.deathDate?.year;
    if (b == null && d == null) return p.isLiving ? 'Living' : 'Deceased';
    final String birth = b?.toString() ?? '?';
    final String death = d?.toString() ?? (p.isLiving ? 'Living' : '?');
    return '$birth–$death';
  }

  static String _initials(Person p) {
    final String a = p.givenName.trim().isNotEmpty ? p.givenName.trim()[0] : '';
    final String b = p.surname.trim().isNotEmpty ? p.surname.trim()[0] : '';
    final String initials = '$a$b'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  /// [p]'s (father, mother). Sex decides the slot where it's known; parents
  /// of unknown sex fill whichever slot is still free, in stored order.
  static (Person?, Person?) _parentsOf(Person? p, Map<String, Person> people) {
    if (p == null) return (null, null);
    final List<Person> parents = <Person>[
      for (final String id in p.parentIds)
        if (people[id] != null) people[id]!,
    ];
    Person? father;
    Person? mother;
    final List<Person> rest = <Person>[];
    for (final Person parent in parents) {
      if (parent.sex == Sex.male && father == null) {
        father = parent;
      } else if (parent.sex == Sex.female && mother == null) {
        mother = parent;
      } else {
        rest.add(parent);
      }
    }
    for (final Person parent in rest) {
      if (father == null) {
        father = parent;
      } else {
        mother ??= parent;
      }
    }
    return (father, mother);
  }

  /// Generation 0 is `[person]`; generation g holds 2^g slots ordered
  /// father-before-mother, so slot i's parents are slots 2i and 2i+1 of the
  /// next generation. Unknown ancestors are null.
  static List<List<Person?>> _ancestorGenerations(
    Person person,
    Map<String, Person> people,
    int depth,
  ) {
    final List<List<Person?>> gens = <List<Person?>>[
      <Person?>[person],
    ];
    for (int g = 1; g <= depth; g++) {
      final List<Person?> row = <Person?>[];
      for (final Person? child in gens[g - 1]) {
        final (Person? father, Person? mother) = _parentsOf(child, people);
        row
          ..add(father)
          ..add(mother);
      }
      gens.add(row);
    }
    return gens;
  }

  static List<Person> _spousesOf(Person p, Map<String, Person> people) =>
      <Person>[
        for (final String id in p.spouseIds)
          if (people[id] != null) people[id]!,
      ];

  static List<Person> _childrenOf(Person p, Map<String, Person> people) {
    final List<Person> children = people.values
        .where((Person c) => c.parentIds.contains(p.id))
        .toList();
    children.sort((Person a, Person b) {
      final DateTime? da = a.birthDate;
      final DateTime? db = b.birthDate;
      if (da == null && db == null) return a.fullName.compareTo(b.fullName);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return children;
  }

  // -------------------------------------------------------------- pedigree

  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// "12 January 1945" — the long form a pedigree chart form is filled in
  /// with. Empty for an unknown date.
  static String _longDate(DateTime? d) =>
      d == null ? '' : '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  /// The marriage of [a] and [b], if either has one on their timeline.
  static TimelineEvent? _marriageOf(Person? a, Person? b) {
    for (final Person? p in <Person?>[a, b]) {
      if (p == null) continue;
      for (final TimelineEvent e in p.events) {
        if (e.type == LifeEventType.marriage) return e;
      }
    }
    return null;
  }

  /// The traditional numbered pedigree chart form: person 1 on the left,
  /// their parents (2–3) beside them, grandparents (4–7) in the middle
  /// column and great-grandparents (8–15) on the right. Every position is
  /// printed — unknown ancestors are left as blank lines to fill in by hand.
  static pw.Page _pedigreePage(
    Person person,
    Map<String, Person> people,
    ChartFonts f,
    PdfPageFormat format,
  ) {
    final PdfPageFormat pf = format.portrait;
    final List<List<Person?>> gens = _ancestorGenerations(person, people, 3);
    // Ahnentafel numbering: n's father is 2n, mother 2n+1.
    Person? at(int n) {
      final int g = n.bitLength - 1;
      return gens[g][n - (1 << g)];
    }

    final List<Person> spouses = _spousesOf(person, people);
    final Person? spouse = spouses.isEmpty ? null : spouses.first;

    String role(int n) {
      if (n == 1) return 'Name';
      if (n == 2) return 'Father';
      if (n == 3) return 'Mother';
      return n.isEven ? 'Father of no. ${n ~/ 2}' : 'Mother of no. ${n ~/ 2}';
    }

    const pw.BorderSide rule = pw.BorderSide(color: _line, width: 0.5);
    const pw.BorderSide heavy = pw.BorderSide(color: _ink, width: 1);

    // Label on its own line, value on a ruled line beneath (columns 1–2).
    pw.Widget stacked(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.SizedBox(height: 2.5),
        pw.Text(label, style: _ts(f, 6.5, color: _muted)),
        pw.Container(
          height: 11,
          alignment: pw.Alignment.bottomLeft,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: rule)),
          child: pw.Text(value, maxLines: 1, style: _ts(f, 8)),
        ),
      ],
    );

    // Label and value sharing one ruled line (the tighter third column).
    pw.Widget inline(String label, String value) => pw.SizedBox(
      height: 10.5,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 44,
            child: pw.Text(label, style: _ts(f, 6, color: _muted)),
          ),
          pw.Expanded(
            child: pw.Container(
              alignment: pw.Alignment.bottomLeft,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: rule),
              ),
              child: pw.Text(value, maxLines: 1, style: _ts(f, 7.5)),
            ),
          ),
        ],
      ),
    );

    pw.Widget nameLine(String number, Person? p) {
      final String code = (p?.code ?? '').trim();
      return pw.Container(
        height: 12,
        alignment: pw.Alignment.bottomLeft,
        padding: const pw.EdgeInsets.only(bottom: 1.5),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: heavy)),
        child: pw.Text(
          <String>[
            number,
            if (p != null) p.fullName,
            if (code.isNotEmpty) '($code)',
          ].join(' '),
          maxLines: 1,
          style: _ts(f, 8),
        ),
      );
    }

    /// One numbered position. Fathers carry the couple's marriage lines,
    /// as on the standard form; [compact] is the third column's layout.
    pw.Widget block(int n, {bool compact = false}) {
      final Person? p = at(n);
      final bool withMarriage = n == 1 || n.isEven;
      final TimelineEvent? marriage = !withMarriage
          ? null
          : n == 1
          ? _marriageOf(p, spouse)
          : _marriageOf(p, at(n + 1));
      final pw.Widget Function(String, String) field = compact
          ? inline
          : stacked;
      final pw.Widget fields = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Text(role(n), style: _ts(f, 7, bold: true)),
          pw.SizedBox(height: compact ? 0 : 2),
          field('Birth date', _longDate(p?.birthDate)),
          field('Birthplace', (p?.birthPlace ?? '').trim()),
          if (withMarriage) ...<pw.Widget>[
            field('Marriage date', _longDate(marriage?.date)),
            field('Marriage place', (marriage?.place ?? '').trim()),
          ],
          field('Death date', _longDate(p?.deathDate)),
          field('Death place', (p?.deathPlace ?? '').trim()),
        ],
      );
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          nameLine('$n', p),
          pw.Container(
            padding: const pw.EdgeInsets.only(left: 4, top: 2),
            decoration: const pw.BoxDecoration(border: pw.Border(left: heavy)),
            child: compact
                ? pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: <pw.Widget>[
                      pw.Expanded(child: fields),
                      pw.SizedBox(width: 4),
                      pw.SizedBox(
                        width: 30,
                        child: pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: <pw.Widget>[
                            pw.Text(
                              'Cont. on chart no.',
                              textAlign: pw.TextAlign.center,
                              style: _ts(f, 5.5, color: _muted),
                            ),
                            pw.Container(
                              height: 9,
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(bottom: rule),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : fields,
          ),
        ],
      );
    }

    final pw.Widget spouseBlock = pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        nameLine('', spouse),
        pw.Container(
          padding: const pw.EdgeInsets.only(left: 4, top: 2),
          decoration: const pw.BoxDecoration(border: pw.Border(left: heavy)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              pw.Text('Spouse', style: _ts(f, 7, bold: true)),
              pw.SizedBox(height: 2),
              stacked('Birth date', _longDate(spouse?.birthDate)),
              stacked('Birthplace', (spouse?.birthPlace ?? '').trim()),
            ],
          ),
        ),
      ],
    );

    pw.Widget blank(double width) => pw.Container(
      width: width,
      height: 10,
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: rule)),
    );

    pw.Widget slot(pw.Widget child, {int flex = 1}) => pw.Expanded(
      flex: flex,
      child: pw.Align(alignment: pw.Alignment.centerLeft, child: child),
    );

    const double indent = 16;
    return pw.Page(
      pageFormat: pf,
      margin: const pw.EdgeInsets.all(_margin),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text('Pedigree Chart', style: _ts(f, 13, bold: true)),
              ),
              pw.Text(
                'Printed: ${_longDate(DateTime.now())}',
                style: _ts(f, 6.5, color: _muted),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text('This is pedigree chart no. ', style: _ts(f, 8)),
              blank(36),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('No 1 on this chart also found on:', style: _ts(f, 8)),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text('Chart ', style: _ts(f, 8)),
              blank(36),
              pw.SizedBox(width: 40),
              pw.Text('Position ', style: _ts(f, 8)),
              blank(36),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: <pw.Widget>[
                // Person 1 with their spouse, the parents set in above and
                // below them.
                pw.Expanded(
                  flex: 10,
                  child: pw.Column(
                    children: <pw.Widget>[
                      slot(
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: indent),
                          child: block(2),
                        ),
                        flex: 5,
                      ),
                      slot(
                        pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: <pw.Widget>[
                            block(1),
                            pw.SizedBox(height: 10),
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(left: indent),
                              child: spouseBlock,
                            ),
                          ],
                        ),
                        flex: 7,
                      ),
                      slot(
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: indent),
                          child: block(3),
                        ),
                        flex: 5,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  flex: 9,
                  child: pw.Column(
                    children: <pw.Widget>[
                      for (int n = 4; n <= 7; n++) slot(block(n)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  flex: 11,
                  child: pw.Column(
                    children: <pw.Widget>[
                      for (int n = 8; n <= 15; n++)
                        slot(block(n, compact: true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------- portrait pedigree

  /// Fetches the photos of [people] that are plain web URLs. Anything that
  /// can't be fetched in time (offline, local-only file, slow link) is left
  /// out and that person falls back to an initials avatar.
  static Future<Map<String, pw.ImageProvider>> _loadPhotos(
    Iterable<Person> people,
  ) async {
    final Map<String, pw.ImageProvider> photos = <String, pw.ImageProvider>{};
    await Future.wait(<Future<void>>[
      for (final Person p in people)
        if ((p.photoUrl ?? '').startsWith('http'))
          () async {
            try {
              photos[p.id] = await networkImage(
                p.photoUrl!,
              ).timeout(const Duration(seconds: 8));
            } catch (_) {
              // Initials avatar instead.
            }
          }(),
    ]);
    return photos;
  }

  static pw.Widget _avatar(
    Person p,
    double diameter,
    Map<String, pw.ImageProvider> photos,
    ChartFonts f,
  ) {
    final pw.ImageProvider? photo = photos[p.id];
    return pw.Container(
      width: diameter,
      height: diameter,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: _fill(p.sex),
        border: pw.Border.all(color: _tint(p.sex), width: 1.5),
      ),
      child: photo != null
          ? pw.ClipOval(child: pw.Image(photo, fit: pw.BoxFit.cover))
          : pw.Center(
              child: pw.Text(
                _initials(p),
                style: _ts(f, diameter * 0.34, bold: true, color: _tint(p.sex)),
              ),
            ),
    );
  }

  static pw.Page _portraitPage(
    _PortraitData data,
    Map<String, pw.ImageProvider> photos,
    ChartFonts f,
    PdfPageFormat format,
  ) {
    final PdfPageFormat pf = format.portrait;
    final double w = pf.width - _margin * 2;
    final double h = pf.height - _margin * 2 - _headerH;
    final List<List<Person?>> gens = data.gens;

    // Rows run top → bottom: great-grandparents, grandparents, parents,
    // the focus person (with spouses), then children.
    final bool hasChildren = data.children.isNotEmpty;
    final int rows = hasChildren ? 5 : 4;
    final double rowH = h / rows;
    double rowCenter(int row) => (row + 0.5) * rowH;
    int rowOfGen(int g) => 3 - g;

    const List<double> avatarD = <double>[62, 54, 46, 34];
    const List<double> cardW = <double>[130, 150, 120, 62];
    const List<double> nameSize = <double>[11, 10, 9, 7.5];
    double cardH(int g) => avatarD[g] + (g == 3 ? 34 : 38);
    double xCenter(int g, int i) => (i + 0.5) * w / (1 << g);

    pw.Widget card(Person p, int g) => pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        _avatar(p, avatarD[g], photos, f),
        pw.SizedBox(height: 3),
        pw.Text(
          p.fullName,
          maxLines: 2,
          textAlign: pw.TextAlign.center,
          style: _ts(f, nameSize[g], bold: true),
        ),
        pw.Text(
          _years(p),
          maxLines: 1,
          textAlign: pw.TextAlign.center,
          style: _ts(f, nameSize[g] - 1, color: _muted),
        ),
      ],
    );

    pw.Widget placed(Person p, int g, double cx, double cy) => pw.Positioned(
      left: cx - cardW[g] / 2,
      top: cy - cardH(g) / 2,
      child: pw.SizedBox(
        width: cardW[g],
        height: cardH(g),
        child: pw.Container(
          color: _white,
          alignment: pw.Alignment.topCenter,
          child: card(p, g),
        ),
      ),
    );

    // Spouses sit beside the focus person: first to the right, second left.
    final List<Person> spouses = data.spouses.take(2).toList();
    final double focusY = rowCenter(rowOfGen(0));
    double spouseX(int index) => w / 2 + (index == 0 ? 1 : -1) * 160;

    // Children share the bottom row, in the smallest card size.
    const int maxChildren = 8;
    final List<Person> children = data.children.take(maxChildren).toList();
    final int hiddenChildren = data.children.length - children.length;
    final double childY = rowCenter(4);
    double childX(int i) => (i + 0.5) * w / children.length;

    return pw.Page(
      pageFormat: pf,
      margin: const pw.EdgeInsets.all(_margin),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          _header(f, 'Portrait pedigree', data.person.fullName),
          pw.SizedBox(
            width: w,
            height: h,
            child: pw.Stack(
              children: <pw.Widget>[
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    size: PdfPoint(w, h),
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      canvas
                        ..setStrokeColor(_line)
                        ..setLineWidth(0.75);
                      double y(double top) => size.y - top;
                      // Child → each known parent, as an elbow through the
                      // gap between the two rows.
                      for (int g = 0; g < 3; g++) {
                        final double childTop =
                            rowCenter(rowOfGen(g)) - cardH(g) / 2;
                        final double parentBottom =
                            rowCenter(rowOfGen(g + 1)) + cardH(g + 1) / 2;
                        final double midY = (childTop + parentBottom) / 2;
                        for (int i = 0; i < (1 << g); i++) {
                          if (gens[g][i] == null) continue;
                          for (final int slot in <int>[i * 2, i * 2 + 1]) {
                            if (gens[g + 1][slot] == null) continue;
                            canvas
                              ..moveTo(xCenter(g, i), y(childTop))
                              ..lineTo(xCenter(g, i), y(midY))
                              ..lineTo(xCenter(g + 1, slot), y(midY))
                              ..lineTo(xCenter(g + 1, slot), y(parentBottom))
                              ..strokePath();
                          }
                        }
                      }
                      for (int s = 0; s < spouses.length; s++) {
                        canvas
                          ..moveTo(w / 2, y(focusY - 10))
                          ..lineTo(spouseX(s), y(focusY - 10))
                          ..strokePath();
                      }
                      if (children.isNotEmpty) {
                        final double focusBottom = focusY + cardH(0) / 2;
                        final double childTop = childY - cardH(3) / 2;
                        final double midY = (focusBottom + childTop) / 2;
                        for (int i = 0; i < children.length; i++) {
                          canvas
                            ..moveTo(w / 2, y(focusBottom))
                            ..lineTo(w / 2, y(midY))
                            ..lineTo(childX(i), y(midY))
                            ..lineTo(childX(i), y(childTop))
                            ..strokePath();
                        }
                      }
                    },
                  ),
                ),
                for (int g = 3; g >= 1; g--)
                  for (int i = 0; i < (1 << g); i++)
                    if (gens[g][i] != null)
                      placed(
                        gens[g][i]!,
                        g,
                        xCenter(g, i),
                        rowCenter(rowOfGen(g)),
                      ),
                for (int s = 0; s < spouses.length; s++)
                  placed(spouses[s], 2, spouseX(s), focusY),
                placed(data.person, 0, w / 2, focusY),
                for (int i = 0; i < children.length; i++)
                  placed(children[i], 3, childX(i), childY),
                if (hiddenChildren > 0)
                  pw.Positioned(
                    right: 0,
                    bottom: 0,
                    child: pw.Text(
                      '+ $hiddenChildren more '
                      '${hiddenChildren == 1 ? 'child' : 'children'}',
                      style: _ts(f, 8, color: _muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- fan chart

  static pw.Page _fanPage(
    Person person,
    Map<String, Person> people,
    ChartFonts f,
    PdfPageFormat format,
  ) {
    final PdfPageFormat pf = format.landscape;
    final double availW = pf.width - _margin * 2;
    final double availH = pf.height - _margin * 2 - _headerH;
    const int depth = 4;
    final List<List<Person?>> gens = _ancestorGenerations(
      person,
      people,
      depth,
    );

    // A half-circle fan: the focus person is the hub at bottom-centre and
    // each ancestor generation is a ring split into 2^g wedges, paternal
    // side on the left.
    final double radius = math.min(availW / 2, availH);
    final double hub = radius * 0.18;
    final double ring = (radius - hub) / depth;
    final double w = radius * 2;
    final double h = radius;
    const List<double> nameSize = <double>[11, 10, 9, 8, 7];

    double inner(int g) => hub + (g - 1) * ring;
    double sweep(int g) => math.pi / (1 << g);
    // Angle (anticlockwise from the positive x axis) of wedge i's centre.
    double theta(int g, int i) => math.pi - (i + 0.5) * sweep(g);

    pw.Widget label(Person p, int g, double boxW, double boxH) => pw.SizedBox(
      width: boxW,
      height: boxH,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            p.fullName,
            maxLines: g == depth ? 2 : 3,
            textAlign: pw.TextAlign.center,
            style: _ts(f, nameSize[g], bold: true),
          ),
          pw.Text(
            _years(p),
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: _ts(f, nameSize[g] - 1, color: _muted),
          ),
        ],
      ),
    );

    final List<pw.Widget> labels = <pw.Widget>[];
    for (int g = 1; g <= depth; g++) {
      final double mid = inner(g) + ring / 2;
      // The outermost ring's wedges are too narrow for text along the arc,
      // so names there run along the radius instead.
      final bool radial = g == depth;
      final double boxW = radial
          ? ring - 8
          : 2 * mid * math.sin(sweep(g) / 2) - 12;
      final double boxH = radial ? mid * sweep(g) - 6 : ring - 8;
      for (int i = 0; i < (1 << g); i++) {
        final Person? p = gens[g][i];
        if (p == null) continue;
        final double t = theta(g, i);
        final double angle = radial
            ? (t <= math.pi / 2 ? t : t - math.pi)
            : t - math.pi / 2;
        labels.add(
          pw.Positioned(
            left: radius + mid * math.cos(t) - boxW / 2,
            top: radius - mid * math.sin(t) - boxH / 2,
            child: pw.Transform.rotate(
              angle: angle,
              child: label(p, g, boxW, boxH),
            ),
          ),
        );
      }
    }

    return pw.Page(
      pageFormat: pf,
      margin: const pw.EdgeInsets.all(_margin),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          _header(f, 'Fan chart', person.fullName),
          pw.Expanded(
            child: pw.Center(
              child: pw.SizedBox(
                width: w,
                height: h,
                child: pw.Stack(
                  children: <pw.Widget>[
                    pw.Positioned.fill(
                      child: pw.CustomPaint(
                        size: PdfPoint(w, h),
                        painter: (PdfGraphics canvas, PdfPoint size) {
                          // Origin is the hub: bottom-centre, y pointing up.
                          final double cx = size.x / 2;
                          void arc(double r, double from, double to) {
                            const int steps = 24;
                            for (int s = 0; s <= steps; s++) {
                              final double a = from + (to - from) * s / steps;
                              canvas.lineTo(
                                cx + r * math.cos(a),
                                r * math.sin(a),
                              );
                            }
                          }

                          canvas
                            ..setStrokeColor(_white)
                            ..setLineWidth(1.5);
                          for (int g = 1; g <= depth; g++) {
                            final double r0 = inner(g);
                            final double r1 = r0 + ring;
                            for (int i = 0; i < (1 << g); i++) {
                              final double a0 = math.pi - i * sweep(g);
                              final double a1 = a0 - sweep(g);
                              final Person? p = gens[g][i];
                              canvas
                                ..setFillColor(
                                  p == null ? _emptyFill : _fill(p.sex),
                                )
                                ..moveTo(
                                  cx + r0 * math.cos(a0),
                                  r0 * math.sin(a0),
                                );
                              arc(r1, a0, a1);
                              arc(r0, a1, a0);
                              canvas
                                ..closePath()
                                ..fillAndStrokePath();
                            }
                          }
                          canvas
                            ..setFillColor(_fill(person.sex))
                            ..moveTo(cx + hub, 0);
                          arc(hub, 0, math.pi);
                          canvas
                            ..closePath()
                            ..fillAndStrokePath();
                        },
                      ),
                    ),
                    ...labels,
                    pw.Positioned(
                      left: radius - hub * 0.8,
                      top: radius - hub * 0.72,
                      child: label(person, 0, hub * 1.6, hub * 0.68),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------- family group record

  /// The traditional family group record form: a husband box, a wife box
  /// and a numbered box per child, each with ruled date/place fields.
  /// Every field is printed — unknown facts are left blank to fill in by
  /// hand. One family (starting on its own page) per spouse or co-parent.
  static pw.MultiPage _groupRecordPage(
    Person person,
    Map<String, Person> people,
    ChartFonts f,
    PdfPageFormat format, {
    List<Record>? records,
  }) {
    final List<_Family> families = _Family.of(person, people);
    final bool withSources = records != null;

    const pw.BorderSide rule = pw.BorderSide(color: _line, width: 0.5);
    const pw.BorderSide heavy = pw.BorderSide(color: _ink, width: 1);
    const double rowH = 22;
    const pw.EdgeInsets cellPad = pw.EdgeInsets.fromLTRB(3, 1.5, 3, 0);

    String named(Person? p) {
      if (p == null) return '';
      final String code = (p.code ?? '').trim();
      return code.isEmpty ? p.fullName : '${p.fullName} ($code)';
    }

    TimelineEvent? eventOf(Person? p, bool Function(TimelineEvent) test) {
      if (p == null) return null;
      for (final TimelineEvent e in p.events) {
        if (test(e)) return e;
      }
      return null;
    }

    TimelineEvent? christening(Person? p) =>
        eventOf(p, (TimelineEvent e) => e.type == LifeEventType.baptism);
    TimelineEvent? burial(Person? p) =>
        eventOf(p, (TimelineEvent e) => e.title.toLowerCase().contains('buri'));

    pw.Widget labelled(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(label, style: _ts(f, 6, color: _muted)),
        pw.Text(value, maxLines: 1, style: _ts(f, 8.5)),
      ],
    );

    pw.Widget cell(
      String label,
      String value, {
      bool first = false,
      int flex = 1,
    }) => pw.Expanded(
      flex: flex,
      child: pw.Container(
        height: rowH,
        padding: cellPad,
        decoration: pw.BoxDecoration(
          border: pw.Border(top: rule, left: first ? pw.BorderSide.none : rule),
        ),
        child: labelled(label, value),
      ),
    );

    pw.Widget factRow(
      String dateLabel,
      DateTime? date,
      String placeLabel,
      String? place,
    ) => pw.Row(
      children: <pw.Widget>[
        cell(dateLabel, _longDate(date), first: true, flex: 2),
        cell(placeLabel, (place ?? '').trim(), flex: 5),
      ],
    );

    pw.Widget tick(String label, bool on) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Container(
          width: 6.5,
          height: 6.5,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.5),
          ),
          child: on ? pw.Text('x', style: _ts(f, 6, bold: true)) : null,
        ),
        pw.SizedBox(width: 3),
        pw.Text(label, style: _ts(f, 6.5)),
      ],
    );

    pw.Widget parentRow(String label, Person? parent) => pw.Container(
      height: rowH,
      padding: cellPad,
      decoration: const pw.BoxDecoration(border: pw.Border(top: rule)),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(child: labelled(label, named(parent))),
          pw.SizedBox(
            width: 70,
            child: tick('Deceased', parent != null && !parent.isLiving),
          ),
        ],
      ),
    );

    pw.Widget noteRow(String text) => pw.Container(
      constraints: const pw.BoxConstraints(minHeight: rowH),
      padding: const pw.EdgeInsets.fromLTRB(3, 1.5, 3, 3),
      decoration: const pw.BoxDecoration(border: pw.Border(top: rule)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'Other parents and other spouses',
            style: _ts(f, 6, color: _muted),
          ),
          if (text.isNotEmpty) pw.Text(text, style: _ts(f, 7.5)),
        ],
      ),
    );

    /// "Other spouses: A (CODE). B (CODE)." — [p]'s spouses besides [not].
    String otherSpouses(Person? p, Person? not) {
      if (p == null) return '';
      final List<String> names = <String>[
        for (final Person s in _spousesOf(p, people))
          if (s.id != not?.id) named(s),
      ];
      return names.isEmpty ? '' : 'Other spouses: ${names.join('. ')}.';
    }

    pw.Widget parentBox(
      String role,
      Person? p,
      Person? partner,
      TimelineEvent? marriage, {
      required bool withMarriage,
    }) {
      final (Person? father, Person? mother) = _parentsOf(p, people);
      final TimelineEvent? chr = christening(p);
      final TimelineEvent? bur = burial(p);
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: heavy, left: rule, right: rule, bottom: rule),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(3, 3, 3, 3),
              child: pw.Row(
                children: <pw.Widget>[
                  pw.Text(role, style: _ts(f, 9.5, bold: true)),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(named(p), maxLines: 1, style: _ts(f, 9.5)),
                  ),
                ],
              ),
            ),
            factRow('Birth date', p?.birthDate, 'Birthplace', p?.birthPlace),
            factRow(
              'Christening date',
              chr?.date,
              'Christening place',
              chr?.place,
            ),
            if (withMarriage)
              factRow(
                'Marriage date',
                marriage?.date,
                'Marriage place',
                marriage?.place,
              ),
            factRow('Death date', p?.deathDate, 'Death place', p?.deathPlace),
            factRow('Burial date', bur?.date, 'Burial place', bur?.place),
            parentRow("$role's father", father),
            parentRow("$role's mother", mother),
            noteRow(otherSpouses(p, partner)),
          ],
        ),
      );
    }

    pw.Widget childBox(int number, Person c) {
      final List<Person> spouses = _spousesOf(c, people);
      final Person? spouse = spouses.isEmpty ? null : spouses.first;
      final TimelineEvent? marriage = _marriageOf(c, spouse);
      final TimelineEvent? chr = christening(c);
      return pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(left: rule, right: rule, bottom: rule),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Container(
              width: 18,
              padding: const pw.EdgeInsets.only(top: 4),
              alignment: pw.Alignment.topCenter,
              child: pw.Text('$number', style: _ts(f, 8.5)),
            ),
            pw.Expanded(
              child: pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(left: rule),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: <pw.Widget>[
                    pw.Container(
                      height: rowH,
                      padding: cellPad,
                      child: pw.Row(
                        children: <pw.Widget>[
                          pw.Expanded(child: labelled('Name', named(c))),
                          pw.SizedBox(
                            width: 70,
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: <pw.Widget>[
                                tick('Male', c.sex == Sex.male),
                                pw.SizedBox(height: 2),
                                tick('Female', c.sex == Sex.female),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    factRow(
                      'Birth date',
                      c.birthDate,
                      'Birthplace',
                      c.birthPlace,
                    ),
                    factRow(
                      'Christening date',
                      chr?.date,
                      'Christening place',
                      chr?.place,
                    ),
                    pw.Row(
                      children: <pw.Widget>[
                        cell(
                          'Marriage date',
                          _longDate(marriage?.date),
                          first: true,
                          flex: 4,
                        ),
                        cell(
                          'Marriage place',
                          (marriage?.place ?? '').trim(),
                          flex: 5,
                        ),
                        cell('Spouse', named(spouse), flex: 5),
                      ],
                    ),
                    factRow(
                      'Death date',
                      c.deathDate,
                      'Death place',
                      c.deathPlace,
                    ),
                    noteRow(otherSpouses(c, spouse)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pw.Widget childrenHeader = pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: heavy, left: rule, right: rule, bottom: rule),
      ),
      child: pw.Text('Children', style: _ts(f, 9.5, bold: true)),
    );

    List<pw.Widget> sources(List<Person> members) {
      final List<pw.Widget> out = <pw.Widget>[
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: heavy, bottom: rule),
          ),
          child: pw.Text('Sources', style: _ts(f, 9.5, bold: true)),
        ),
      ];
      bool any = false;
      for (final Person member in members) {
        final List<Record> own = records!
            .where((Record r) => r.personIds.contains(member.id))
            .toList();
        if (own.isEmpty) continue;
        any = true;
        out.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 2, left: 3),
            child: pw.Text(named(member), style: _ts(f, 9, bold: true)),
          ),
        );
        for (int i = 0; i < own.length; i++) {
          final Record r = own[i];
          final String meta = <String>[
            r.type.label,
            if (r.repository.trim().isNotEmpty) r.repository.trim(),
            if (r.date != null) _longDate(r.date),
          ].join(' · ');
          out.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3, left: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text('${i + 1}. ${r.title}', style: _ts(f, 8.5)),
                  pw.Text(meta, style: _ts(f, 7.5, color: _muted)),
                  if (r.citation.trim().isNotEmpty)
                    pw.Text(
                      r.citation.trim(),
                      style: _ts(f, 7.5, color: _muted),
                    ),
                ],
              ),
            ),
          );
        }
      }
      if (!any) {
        out.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, left: 3),
            child: pw.Text(
              'No sources are attached to this family yet.',
              style: _ts(f, 8.5, color: _muted),
            ),
          ),
        );
      }
      return out;
    }

    List<pw.Widget> familyWidgets(_Family family) {
      // A family with only one known parent still prints both boxes, the
      // other left blank.
      final Person? husband = family.partner != null
          ? family.parents.first
          : (person.sex == Sex.female ? null : person);
      final Person? wife = family.partner != null
          ? family.parents.last
          : (person.sex == Sex.female ? person : null);
      final TimelineEvent? marriage = family.marriage;
      return <pw.Widget>[
        parentBox('Husband', husband, wife, marriage, withMarriage: true),
        parentBox('Wife', wife, husband, marriage, withMarriage: false),
        childrenHeader,
        for (int i = 0; i < family.children.length; i++)
          childBox(i + 1, family.children[i]),
        if (withSources)
          ...sources(<Person>[?husband, ?wife, ...family.children]),
      ];
    }

    pw.Widget blank(double width) => pw.Container(
      width: width,
      height: 9,
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: rule)),
    );

    return pw.MultiPage(
      pageFormat: format.portrait,
      margin: const pw.EdgeInsets.all(_margin),
      header: (pw.Context context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                'Family Group Record',
                style: _ts(f, 13, bold: true),
              ),
            ),
            pw.Text('Family group record number ', style: _ts(f, 7)),
            blank(40),
            pw.SizedBox(width: 16),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: _ts(f, 7),
            ),
          ],
        ),
      ),
      build: (pw.Context context) => <pw.Widget>[
        for (int i = 0; i < families.length; i++) ...<pw.Widget>[
          if (i > 0) pw.NewPage(),
          ...familyWidgets(families[i]),
        ],
      ],
    );
  }
}

/// Everyone drawn on the portrait pedigree, gathered up front so their
/// photos can be fetched before the (synchronous) page layout runs.
class _PortraitData {
  _PortraitData._(this.person, this.gens, this.spouses, this.children);

  factory _PortraitData.of(Person person, Map<String, Person> people) =>
      _PortraitData._(
        person,
        FamilyChartPdfService._ancestorGenerations(person, people, 3),
        FamilyChartPdfService._spousesOf(person, people),
        FamilyChartPdfService._childrenOf(person, people),
      );

  final Person person;
  final List<List<Person?>> gens;
  final List<Person> spouses;
  final List<Person> children;

  Iterable<Person> get everyone => <Person>[
    for (final List<Person?> gen in gens) ...gen.whereType<Person>(),
    ...spouses,
    ...children,
  ];
}

/// One family the focus person heads: them, a partner (if any), and the
/// children they share.
class _Family {
  _Family(this.person, this.partner, this.children);

  final Person person;
  final Person? partner;
  final List<Person> children;

  /// Husband first, the way a family group record is traditionally laid out.
  List<Person> get parents {
    if (partner == null) return <Person>[person];
    return person.sex == Sex.female || partner!.sex == Sex.male
        ? <Person>[partner!, person]
        : <Person>[person, partner!];
  }

  /// The couple's marriage, if either of them has it on their timeline.
  TimelineEvent? get marriage {
    if (partner == null) return null;
    for (final Person p in <Person>[person, partner!]) {
      for (final TimelineEvent e in p.events) {
        if (e.type == LifeEventType.marriage) return e;
      }
    }
    return null;
  }

  /// One family per spouse or co-parent, plus one for any children with no
  /// other known parent. Always returns at least one family.
  static List<_Family> of(Person person, Map<String, Person> people) {
    final List<Person> children = FamilyChartPdfService._childrenOf(
      person,
      people,
    );
    final List<Person> partners = FamilyChartPdfService._spousesOf(
      person,
      people,
    );
    final Set<String> partnerIds = partners.map((Person p) => p.id).toSet();
    for (final Person child in children) {
      for (final String id in child.parentIds) {
        if (id == person.id || partnerIds.contains(id)) continue;
        final Person? coParent = people[id];
        if (coParent == null) continue;
        partners.add(coParent);
        partnerIds.add(id);
      }
    }

    final List<_Family> families = <_Family>[
      for (final Person partner in partners)
        _Family(
          person,
          partner,
          children
              .where((Person c) => c.parentIds.contains(partner.id))
              .toList(),
        ),
    ];
    final List<Person> alone = children
        .where((Person c) => !c.parentIds.any(partnerIds.contains))
        .toList();
    if (alone.isNotEmpty || families.isEmpty) {
      families.add(_Family(person, null, alone));
    }
    return families;
  }
}

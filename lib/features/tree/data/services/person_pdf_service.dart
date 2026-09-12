import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/person.dart';
import '../../domain/entities/timeline_event.dart';

/// Renders a single person's vital details + life story to a one-page,
/// printable PDF — the "Print or export" action on their profile.
class PersonPdfService {
  PersonPdfService._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF1C1917);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B6660);
  static const PdfColor _line = PdfColor.fromInt(0xFFE7E1DA);

  static Future<Uint8List> build({
    required Person person,
    required List<TimelineEvent> events,
    required PdfPageFormat format,
  }) async {
    final pw.Font body = await PdfGoogleFonts.dMSansRegular();
    final pw.Font bodyBold = await PdfGoogleFonts.dMSansBold();
    final pw.Font display = await PdfGoogleFonts.playfairDisplayBold();
    final List<pw.Font> fallback = <pw.Font>[
      await PdfGoogleFonts.notoSansRegular(),
    ];

    final doc = pw.Document();

    String yearSpan() {
      final int? b = person.birthDate?.year;
      final int? d = person.deathDate?.year;
      if (b == null && d == null) return person.isLiving ? 'Living' : '';
      final String birth = b?.toString() ?? '?';
      final String death = d?.toString() ?? (person.isLiving ? 'Living' : '?');
      return '$birth–$death';
    }

    final List<MapEntry<String, String>> details = <MapEntry<String, String>>[
      if ((person.nickname ?? '').trim().isNotEmpty)
        MapEntry('Nickname', person.nickname!.trim()),
      if ((person.otherNames ?? '').trim().isNotEmpty)
        MapEntry('Other names', person.otherNames!.trim()),
      if (person.birthPlace != null && person.birthPlace!.trim().isNotEmpty)
        MapEntry('Birth place', person.birthPlace!.trim()),
      if ((person.deathPlace ?? '').trim().isNotEmpty)
        MapEntry('Death place', person.deathPlace!.trim()),
      if ((person.occupation ?? '').trim().isNotEmpty)
        MapEntry('Occupation', person.occupation!.trim()),
      if ((person.education ?? '').trim().isNotEmpty)
        MapEntry('Education', person.education!.trim()),
      if ((person.religion ?? '').trim().isNotEmpty)
        MapEntry('Religion', person.religion!.trim()),
      if ((person.language ?? '').trim().isNotEmpty)
        MapEntry('Language', person.language!.trim()),
      if (person.location.isNotEmpty) MapEntry('Location', person.location),
    ];

    pw.Widget sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
      child: pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          font: bodyBold,
          fontFallback: fallback,
          fontSize: 10,
          letterSpacing: 0.6,
          color: _muted,
        ),
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                person.fullName,
                style: pw.TextStyle(
                  font: display,
                  fontFallback: fallback,
                  fontSize: 26,
                  color: _ink,
                ),
              ),
              if (yearSpan().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(
                    yearSpan(),
                    style: pw.TextStyle(
                      font: body,
                      fontFallback: fallback,
                      fontSize: 12,
                      color: _muted,
                    ),
                  ),
                ),
              if (details.isNotEmpty) ...<pw.Widget>[
                sectionTitle('Vital details'),
                pw.Divider(color: _line, thickness: 1),
                for (final MapEntry<String, String> d in details)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: <pw.TextSpan>[
                          pw.TextSpan(
                            text: '${d.key}: ',
                            style: pw.TextStyle(
                              font: bodyBold,
                              fontFallback: fallback,
                              fontSize: 11,
                              color: _ink,
                            ),
                          ),
                          pw.TextSpan(
                            text: d.value,
                            style: pw.TextStyle(
                              font: body,
                              fontFallback: fallback,
                              fontSize: 11,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (events.isNotEmpty) ...<pw.Widget>[
                sectionTitle('Life story'),
                pw.Divider(color: _line, thickness: 1),
                for (final TimelineEvent e in events)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Text(
                      <String>[
                        if (e.date != null) _formatDate(e.date!),
                        e.title,
                        if ((e.place ?? '').trim().isNotEmpty) e.place!.trim(),
                      ].join(' — '),
                      style: pw.TextStyle(
                        font: body,
                        fontFallback: fallback,
                        fontSize: 11,
                        color: _ink,
                      ),
                    ),
                  ),
              ],
              if ((person.notes ?? '').trim().isNotEmpty) ...<pw.Widget>[
                sectionTitle('Notes'),
                pw.Divider(color: _line, thickness: 1),
                pw.Text(
                  person.notes!.trim(),
                  style: pw.TextStyle(
                    font: body,
                    fontFallback: fallback,
                    fontSize: 11,
                    color: _ink,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

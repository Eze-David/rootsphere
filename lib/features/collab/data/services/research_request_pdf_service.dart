import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../../domain/entities/research_request.dart';

/// Renders a submitted research request as the RootSphere Family History
/// Foundation's "Family History & Genealogy Research Request Form" — same
/// sections (A–F), tick boxes and signature block as the paper original,
/// filled in with the requester's answers.
class ResearchRequestPdfService {
  ResearchRequestPdfService._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF1C1917);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B6660);
  static const PdfColor _line = PdfColor.fromInt(0xFFB9B1A8);
  static const PdfColor _accent = PdfColor.fromInt(0xFF3E2A1E);

  static Future<Uint8List> build({
    required CollaborationOpportunity opportunity,
    required OpportunitySubject subject,
    required PdfPageFormat format,
  }) async {
    final pw.Font body = await PdfGoogleFonts.dMSansRegular();
    final pw.Font bodyBold = await PdfGoogleFonts.dMSansBold();
    final pw.Font display = await PdfGoogleFonts.playfairDisplayBold();
    final List<pw.Font> fallback = <pw.Font>[
      await PdfGoogleFonts.notoSansRegular(),
    ];
    final ResearchRequest r = subject.request;

    pw.TextStyle style({
      pw.Font? font,
      double size = 10,
      PdfColor color = _ink,
    }) => pw.TextStyle(
      font: font ?? body,
      fontFallback: fallback,
      fontSize: size,
      color: color,
    );

    pw.Widget section(String letter, String title) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: _accent,
      child: pw.Text(
        '$letter. ${title.toUpperCase()}',
        style: style(font: bodyBold, size: 10, color: PdfColors.white),
      ),
    );

    // "Label: value" on a ruled line, like the paper form's blanks.
    pw.Widget field(String label, String value) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 5, bottom: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: <pw.InlineSpan>[
            pw.TextSpan(
              text: '$label: ',
              style: style(font: bodyBold, color: _muted),
            ),
            pw.TextSpan(text: value.trim(), style: style()),
          ],
        ),
      ),
    );

    // A heading with a boxed free-text answer below it.
    pw.Widget block(String label, String value, {String? hint}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.SizedBox(height: 6),
        pw.Text(label, style: style(font: bodyBold)),
        if (hint != null) pw.Text(hint, style: style(size: 8, color: _muted)),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          constraints: const pw.BoxConstraints(minHeight: 36),
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.5),
          ),
          child: pw.Text(value.trim(), style: style()),
        ),
      ],
    );

    pw.Widget tick(String label, bool checked) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Container(
          width: 9,
          height: 9,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _ink, width: 0.7),
            color: checked ? _accent : null,
          ),
          child: checked
              ? pw.Text(
                  'x',
                  style: style(font: bodyBold, size: 7, color: PdfColors.white),
                )
              : null,
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: style(size: 9)),
      ],
    );

    pw.Widget ticks(
      List<String> options,
      List<String> selected, {
      String? other,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
      child: pw.Wrap(
        spacing: 12,
        runSpacing: 5,
        children: <pw.Widget>[
          for (final String o in options) tick(o, selected.contains(o)),
          if (other != null)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                tick('Other:', other.trim().isNotEmpty),
                pw.SizedBox(width: 4),
                pw.Text(other.trim(), style: style(size: 9)),
              ],
            ),
        ],
      ),
    );

    String date(DateTime? d) {
      if (d == null) return '';
      final DateTime l = d.toLocal();
      return '${l.day.toString().padLeft(2, '0')}/'
          '${l.month.toString().padLeft(2, '0')}/${l.year}';
    }

    final List<String> documentLines = r.documentsProvided
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final int uploads = subject.photoUrls.length + subject.documentUrls.length;

    final doc = pw.Document(
      title: 'Research Request ${researchReferenceNumber(opportunity.id)}',
      author: 'RootSphere Family History Foundation',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'Research Request · ${researchReferenceNumber(opportunity.id)}',
                  style: style(size: 8, color: _muted),
                ),
              ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'RootSphere Family History Foundation · Reg. No. 9627676',
              style: style(size: 8, color: _muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: style(size: 8, color: _muted),
            ),
          ],
        ),
        build: (context) => <pw.Widget>[
          pw.Center(
            child: pw.Column(
              children: <pw.Widget>[
                pw.Text(
                  'ROOTSPHERE FAMILY HISTORY FOUNDATION',
                  style: style(font: display, size: 18, color: _accent),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Family History & Genealogy Research Request Form',
                  style: style(font: bodyBold, size: 12),
                ),
                pw.SizedBox(height: 2),
                pw.Text('Reg. No.: 9627676', style: style(size: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'Request: ${opportunity.title}',
                style: style(font: bodyBold, size: 9),
              ),
              pw.Text(
                'RootSphere Reference No.: '
                '${researchReferenceNumber(opportunity.id)}',
                style: style(font: bodyBold, size: 9),
              ),
            ],
          ),

          section('A', "Requester's information"),
          field('Full Name', r.requesterName),
          field('Address', r.requesterAddress),
          field('Phone Number', r.requesterPhone),
          field('Email Address', r.requesterEmail),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Row(
              children: <pw.Widget>[
                pw.Text(
                  'Preferred Method of Contact:  ',
                  style: style(font: bodyBold, color: _muted),
                ),
                ticks(ResearchRequest.contactMethodOptions, r.contactMethods),
              ],
            ),
          ),
          field(
            'Relationship to the person/family being researched',
            r.relationship,
          ),

          section('B', 'Person or family to be researched'),
          field('Full Name of Person/Ancestor', subject.fullName),
          field('Other Names/Spellings Used', subject.nickName),
          field('Approximate Date of Birth', r.birthDate),
          field(
            'Place of Birth/Origin',
            <String>[
              r.birthPlace,
              subject.country,
            ].where((s) => s.trim().isNotEmpty).join(', '),
          ),
          field('Date/Place of Marriage', r.marriage),
          field('Date/Place of Death', r.death),
          field('Spouse(s)', r.spouses),
          field('Parents (if known)', r.parents),
          field('Children/Siblings/Other Relatives Known', r.relatives),
          field('Ethnic Group/Community (if relevant)', r.ethnicGroup),
          field('Religion/Church (if relevant)', r.religion),

          section('C', 'Research request'),
          block(
            'Main Research Question',
            r.researchQuestion,
            hint: 'Clearly state what you want the researcher to establish.',
          ),
          block('Information Already Known', subject.additionalInfo ?? ''),
          pw.SizedBox(height: 6),
          pw.Text('Sources Already Checked', style: style(font: bodyBold)),
          ticks(
            ResearchRequest.sourceOptions,
            r.sourcesChecked,
            other: r.sourcesOther,
          ),

          section('D', 'Documents provided'),
          pw.Text(
            'Documents, photographs, certificates, family trees, interview '
            'notes, or other materials supplied with this request.',
            style: style(size: 9, color: _muted),
          ),
          pw.SizedBox(height: 4),
          if (documentLines.isEmpty)
            pw.Bullet(text: '', style: style())
          else
            for (final String line in documentLines)
              pw.Bullet(text: line, style: style()),
          if (uploads > 0)
            pw.Text(
              '$uploads file${uploads == 1 ? '' : 's'} uploaded with this '
              'request in the RootSphere app.',
              style: style(size: 9, color: _muted),
            ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Unless otherwise agreed, original documents should not be '
            'submitted where a clear digital copy will suffice.',
            style: style(size: 8, color: _muted),
          ),

          section('E', 'Desired research output'),
          ticks(
            ResearchRequest.outputOptions,
            r.desiredOutputs,
            other: r.outputsOther,
          ),

          section('F', "Requester's declaration and consent"),
          pw.Text(
            ResearchRequest.declarationText,
            style: style(size: 9),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),
          tick(
            'The requester accepted this declaration in the RootSphere app.',
            r.declarationAccepted,
          ),
          pw.SizedBox(height: 6),
          field('Requester Name', r.requesterName),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                flex: 3,
                child: field(
                  'Signature',
                  r.declarationAccepted
                      ? '${r.requesterName} (signed electronically)'
                      : '',
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(flex: 2, child: field('Date', date(r.declaredAt))),
            ],
          ),
          field(
            'RootSphere Reference No.',
            researchReferenceNumber(opportunity.id),
          ),
        ],
      ),
    );

    return doc.save();
  }
}

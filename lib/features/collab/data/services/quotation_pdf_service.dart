import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/opportunity.dart';
import '../../domain/entities/research_quotation.dart';
import '../../domain/entities/research_request.dart';

/// A RootSphere Family History Foundation quotation for a research request —
/// itemised table, total, timeframe, validity and terms.
class QuotationPdfService {
  QuotationPdfService._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF1C1917);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B6660);
  static const PdfColor _line = PdfColor.fromInt(0xFFB9B1A8);
  static const PdfColor _accent = PdfColor.fromInt(0xFF3E2A1E);
  static const PdfColor _tint = PdfColor.fromInt(0xFFF4EFEA);

  static Future<Uint8List> build({
    required CollaborationOpportunity opportunity,
    required ResearchQuotation quotation,
    required PdfPageFormat format,
  }) async {
    final pw.Font body = await PdfGoogleFonts.dMSansRegular();
    final pw.Font bodyBold = await PdfGoogleFonts.dMSansBold();
    final pw.Font display = await PdfGoogleFonts.playfairDisplayBold();
    // Noto Sans carries the ₦ glyph, which DM Sans lacks.
    final List<pw.Font> fallback = <pw.Font>[
      await PdfGoogleFonts.notoSansRegular(),
    ];

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

    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    pw.Widget meta(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          children: <pw.InlineSpan>[
            pw.TextSpan(
              text: '$label: ',
              style: style(font: bodyBold, size: 9, color: _muted),
            ),
            pw.TextSpan(text: value, style: style(size: 9)),
          ],
        ),
      ),
    );

    pw.Widget cell(
      String text, {
      bool bold = false,
      bool right = false,
      PdfColor color = _ink,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: style(font: bold ? bodyBold : body, color: color),
      ),
    );

    final String statusLine = switch (quotation.status) {
      QuotationStatus.paid =>
        'PAID${quotation.paidAt == null ? '' : ' on ${date(quotation.paidAt!)}'}',
      QuotationStatus.accepted => 'ACCEPTED — awaiting payment',
      QuotationStatus.declined => 'DECLINED',
      QuotationStatus.superseded => 'SUPERSEDED by a revised quotation',
      QuotationStatus.sent =>
        quotation.isExpired ? 'EXPIRED' : 'AWAITING RESPONSE',
    };

    final doc = pw.Document(
      title: 'Quotation ${quotation.reference}',
      author: 'RootSphere Family History Foundation',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'RootSphere Family History Foundation · Reg. No. 9627676 · rootsphere.ink',
              style: style(size: 8, color: _muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: style(size: 8, color: _muted),
            ),
          ],
        ),
        build: (context) => <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'ROOTSPHERE FAMILY HISTORY FOUNDATION',
                    style: style(font: display, size: 15, color: _accent),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Reg. No.: 9627676', style: style(size: 9)),
                ],
              ),
              pw.Text(
                'QUOTATION',
                style: style(font: display, size: 22, color: _accent),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(height: 1.2, color: _accent),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      'PREPARED FOR',
                      style: style(font: bodyBold, size: 8, color: _muted),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      opportunity.requesterName,
                      style: style(font: bodyBold, size: 11),
                    ),
                    pw.SizedBox(height: 6),
                    meta('Research request', opportunity.title),
                    meta(
                      'Request reference',
                      researchReferenceNumber(opportunity.id),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  meta('Quotation No.', quotation.reference),
                  meta('Date issued', date(quotation.createdAt)),
                  if (quotation.validUntil != null)
                    meta('Valid until', date(quotation.validUntil!)),
                  meta('Status', statusLine),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
              bottom: pw.BorderSide(color: _line, width: 0.5),
            ),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(28),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(110),
            },
            children: <pw.TableRow>[
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _accent),
                children: <pw.Widget>[
                  cell('#', bold: true, color: PdfColors.white),
                  cell('Description', bold: true, color: PdfColors.white),
                  cell(
                    'Amount',
                    bold: true,
                    right: true,
                    color: PdfColors.white,
                  ),
                ],
              ),
              for (int i = 0; i < quotation.lineItems.length; i++)
                pw.TableRow(
                  decoration: i.isOdd
                      ? const pw.BoxDecoration(color: _tint)
                      : null,
                  children: <pw.Widget>[
                    cell('${i + 1}'),
                    cell(quotation.lineItems[i].description),
                    cell(
                      formatNaira(quotation.lineItems[i].amountCents),
                      right: true,
                    ),
                  ],
                ),
            ],
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              margin: const pw.EdgeInsets.only(top: 6),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: _accent, width: 1.2),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text('TOTAL', style: style(font: bodyBold, size: 11)),
                  pw.Text(
                    formatNaira(quotation.totalCents),
                    style: style(font: bodyBold, size: 13, color: _accent),
                  ),
                ],
              ),
            ),
          ),
          if (quotation.timeframe.trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 14),
            pw.Text(
              'ESTIMATED TIMEFRAME',
              style: style(font: bodyBold, size: 8, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(quotation.timeframe.trim(), style: style()),
          ],
          if (quotation.notes.trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 14),
            pw.Text(
              'NOTES & TERMS',
              style: style(font: bodyBold, size: 8, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(quotation.notes.trim(), style: style()),
          ],
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            color: _tint,
            child: pw.Text(
              'To proceed, accept this quotation in the RootSphere app and '
              'complete payment. Research begins once payment is confirmed. '
              'Genealogical research depends on the availability and survival '
              'of historical records; RootSphere cannot guarantee that a '
              'requested ancestor, relationship, event or record will be found.',
              style: style(size: 8.5, color: _muted),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }
}

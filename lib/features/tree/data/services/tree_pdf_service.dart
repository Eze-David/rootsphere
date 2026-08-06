import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/person.dart';
import '../../presentation/layout/tree_layout.dart';

/// Renders a [TreeLayout] to a printable PDF page.
///
/// Draws the same cards + connectors the on-screen [TreeConnectorPainter] and
/// `PersonCardWidget` show, scaled to fit a single page. "Add father/mother"
/// placeholder slots are omitted — a printed chart should only show known
/// people. [format] comes from the OS print dialog via `Printing.layoutPdf`'s
/// `onLayout` callback, so re-picking a paper size re-fits the tree to it.
class TreePdfService {
  TreePdfService._();

  static const PdfColor _male = PdfColor.fromInt(0xFF6E86A6);
  static const PdfColor _female = PdfColor.fromInt(0xFFC76A4D);
  static const PdfColor _neutral = PdfColor.fromInt(0xFF9A938B);
  static const PdfColor _ink = PdfColor.fromInt(0xFF1C1917);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B6660);
  static const PdfColor _line = PdfColor.fromInt(0xFF9C968E);
  static const PdfColor _focusBorder = PdfColor.fromInt(0xFF4A362A);
  static const PdfColor _paper = PdfColor.fromInt(0xFFFFFFFF);

  static Future<Uint8List> build({
    required TreeLayout layout,
    required String treeName,
    required String focusName,
    required PdfPageFormat format,
  }) async {
    final pw.Font body = await PdfGoogleFonts.dMSansRegular();
    final pw.Font bodyBold = await PdfGoogleFonts.dMSansBold();
    final pw.Font display = await PdfGoogleFonts.playfairDisplayBold();
    // DM Sans / Playfair Display don't cover the dotted-Latin letters used in
    // Yoruba/Igbo orthography (Ọ, Ṣ, Ụ …); fall back to Noto Sans, which does,
    // so names with those diacritics don't render as tofu boxes.
    final List<pw.Font> fallback = <pw.Font>[await PdfGoogleFonts.notoSansRegular()];

    final doc = pw.Document();

    const double headerHeight = 30;
    const double margin = 24;
    // A tree with many generations/siblings used to always get squeezed onto
    // one fixed-size page, shrinking card text down to an unreadable ~1pt on
    // anything but a small tree. Instead, render every card at its natural
    // size (fit = 1) and size the PDF page itself to match — like a poster
    // print — so names/dates/IDs stay legible regardless of tree size.
    // "Save as PDF" (the common destination) has no physical paper limit;
    // only genuinely enormous trees are shrunk, to stay within what PDF
    // readers can reliably handle as a single page.
    const double maxPdfDimension = 14000;
    final double sceneW = layout.size.width;
    final double sceneH = layout.size.height;
    final double fit = (sceneW <= maxPdfDimension && sceneH <= maxPdfDimension)
        ? 1.0
        : <double>[maxPdfDimension / sceneW, maxPdfDimension / sceneH]
            .reduce((a, b) => a < b ? a : b);

    final double pageW = _maxD(sceneW * fit + margin * 2, format.width);
    final double pageH = _maxD(
      sceneH * fit + margin * 2 + headerHeight,
      format.height,
    );
    final PdfPageFormat pageFormat = PdfPageFormat(
      pageW,
      pageH,
      marginAll: margin,
    );

    final bool wideCards = layout.nodes.isNotEmpty &&
        layout.nodes.first.rect.width > layout.nodes.first.rect.height;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              treeName,
              style: pw.TextStyle(
                font: display,
                fontFallback: fallback,
                fontSize: 16,
                color: _ink,
              ),
            ),
            pw.Text(
              "$focusName's family tree",
              style: pw.TextStyle(
                font: body,
                fontFallback: fallback,
                fontSize: 9,
                color: _muted,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Center(
                child: pw.SizedBox(
                  width: sceneW * fit,
                  height: sceneH * fit,
                  child: pw.Stack(
                    children: <pw.Widget>[
                      pw.Positioned.fill(
                        child: pw.CustomPaint(
                          size: PdfPoint(sceneW * fit, sceneH * fit),
                          painter: (canvas, size) {
                            canvas
                              ..setStrokeColor(_line)
                              ..setLineWidth(0.75);
                            for (final c in layout.connectors) {
                              if (c.points.length < 2) continue;
                              final Offset first = c.points.first;
                              canvas.moveTo(
                                first.dx * fit,
                                size.y - first.dy * fit,
                              );
                              for (final p in c.points.skip(1)) {
                                canvas.lineTo(p.dx * fit, size.y - p.dy * fit);
                              }
                              canvas.strokePath();
                            }
                          },
                        ),
                      ),
                      for (final GenerationLabel label in layout.labels)
                        pw.Positioned(
                          left: label.center.dx * fit - 80 * fit,
                          top: label.center.dy * fit - 8 * fit,
                          child: pw.SizedBox(
                            width: 160 * fit,
                            child: pw.Center(
                              child: pw.Text(
                                label.text,
                                style: pw.TextStyle(
                                  font: body,
                                  fontFallback: fallback,
                                  fontSize: _scaled(11, fit, min: 3),
                                  color: _muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (final PositionedPerson node in layout.nodes)
                        pw.Positioned(
                          left: node.rect.left * fit,
                          top: node.rect.top * fit,
                          child: pw.SizedBox(
                            width: node.rect.width * fit,
                            height: node.rect.height * fit +
                                (wideCards
                                    ? 0
                                    : _detailExtraHeight(node.person, fit)),
                            child: wideCards
                                ? _wideCard(node, body, bodyBold, fallback, fit)
                                : _tallCard(node, body, bodyBold, fallback, fit),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static PdfColor _tintFor(Sex sex) => switch (sex) {
        Sex.male => _male,
        Sex.female => _female,
        Sex.unknown => _neutral,
      };

  static String _initials(Person p) {
    final String a = p.givenName.trim().isNotEmpty ? p.givenName.trim()[0] : '';
    final String b = p.surname.trim().isNotEmpty ? p.surname.trim()[0] : '';
    final String initials = '$a$b'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  static String _yearSpan(Person p) {
    final int? b = p.birthDate?.year;
    final int? d = p.deathDate?.year;
    if (b == null && d == null) return p.isLiving ? 'Living' : '';
    final String birth = b?.toString() ?? '?';
    final String death = d?.toString() ?? (p.isLiving ? 'Living' : '?');
    return '$birth–$death';
  }

  static const double _detailLineFont = 8;
  static const double _detailLineGap = 1.5;

  /// One "Label: value" line per populated field from the profile's DETAILS
  /// section, in the same order it's shown there — printed under the name
  /// on a portrait card so the printout carries everything the on-screen
  /// card does, plus these.
  static List<String> _detailLines(Person p) {
    String? clean(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();
    final List<MapEntry<String, String?>> fields = <MapEntry<String, String?>>[
      MapEntry('Nickname', clean(p.nickname)),
      MapEntry('Other names', clean(p.otherNames)),
      MapEntry('Religion', clean(p.religion)),
      MapEntry('Occupation', clean(p.occupation)),
      MapEntry('Education', clean(p.education)),
      MapEntry('Language', clean(p.language)),
      MapEntry('Location', p.location.isEmpty ? null : p.location),
      MapEntry('Death place', clean(p.deathPlace)),
    ];
    return <String>[
      for (final MapEntry<String, String?> f in fields)
        if (f.value != null) '${f.key}: ${f.value}',
    ];
  }

  /// Extra card height a portrait card needs to fit its detail lines below
  /// the existing name/lifespan/ID block — grows down into the generous gap
  /// between generation rows (104px, vs. only 28px between siblings in
  /// landscape orientation), so this is only safe for portrait cards; see
  /// [_wideCard].
  static double _detailExtraHeight(Person p, double fit) {
    final List<String> lines = _detailLines(p);
    if (lines.isEmpty) return 0;
    final double lineH = _scaled(_detailLineFont, fit) + _detailLineGap * fit;
    return lines.length * lineH + 2 * fit;
  }

  static pw.BoxDecoration _cardDecoration(bool isFocus) => pw.BoxDecoration(
        color: _paper,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(
          // Hairline borders stay a fixed width regardless of `fit` — like
          // the on-screen card borders, they should read at any zoom level
          // rather than shrink away on a big, heavily scaled-down tree.
          color: isFocus ? _focusBorder : _line,
          width: isFocus ? 1.2 : 0.6,
        ),
      );

  /// Scales a base point size by `fit` (how much [build] shrank the whole
  /// tree to fit the page) — proportional scaling keeps text fitting its
  /// (equally shrunk) card exactly as it did unscaled. [min] is a small
  /// absolute floor so a huge tree doesn't produce sub-pixel text; only that
  /// extreme case may clip slightly as a result.
  static double _scaled(double base, double fit, {double min = 2.5}) =>
      (base * fit).clamp(min, base);

  static double _maxD(double a, double b) => a > b ? a : b;

  /// Portrait-style card: tinted "photo" block on top, name + years below.
  /// Mirrors the vertical-orientation `PersonCardWidget`.
  static pw.Widget _tallCard(
    PositionedPerson node,
    pw.Font body,
    pw.Font bodyBold,
    List<pw.Font> fallback,
    double fit,
  ) {
    final Person p = node.person;
    final double pad = _scaled(3, fit, min: 1);
    return pw.Container(
      decoration: _cardDecoration(node.isFocus),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          // Expanded (rather than an absolute height) so the tint block
          // always fills whatever room is left after the text below it,
          // regardless of how much `fit` has scaled the card down.
          pw.Expanded(
            child: pw.Container(
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: _tintFor(p.sex),
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(5),
                  topRight: pw.Radius.circular(5),
                ),
              ),
              child: pw.Text(
                _initials(p),
                style: pw.TextStyle(
                  font: bodyBold,
                  fontFallback: fallback,
                  fontSize: _scaled(20, fit),
                  color: _paper,
                ),
              ),
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: pad, vertical: pad),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Text(
                  p.fullName,
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: bodyBold,
                    fontFallback: fallback,
                    fontSize: _scaled(12, fit),
                    color: _ink,
                  ),
                ),
                pw.Text(
                  _yearSpan(p),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: body,
                    fontFallback: fallback,
                    fontSize: _scaled(10, fit),
                    color: _muted,
                  ),
                ),
                if ((p.code ?? '').isNotEmpty)
                  pw.Text(
                    p.code!,
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: body,
                      fontFallback: fallback,
                      fontSize: _scaled(8.5, fit),
                      color: _muted,
                    ),
                  ),
                for (final line in _detailLines(p))
                  pw.Padding(
                    padding: pw.EdgeInsets.only(top: _detailLineGap * fit),
                    child: pw.Text(
                      line,
                      textAlign: pw.TextAlign.center,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        font: body,
                        fontFallback: fallback,
                        fontSize: _scaled(_detailLineFont, fit),
                        color: _muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Landscape-style card: small tinted avatar beside the name + years.
  /// Mirrors the horizontal-orientation `PersonCardWidget`.
  static pw.Widget _wideCard(
    PositionedPerson node,
    pw.Font body,
    pw.Font bodyBold,
    List<pw.Font> fallback,
    double fit,
  ) {
    final Person p = node.person;
    final double pad = _scaled(4, fit, min: 1);
    // Sized off the (already fit-scaled) card height, so it never asks for
    // more room than the card actually has.
    final double avatarSize =
        (node.rect.height * fit - pad * 2).clamp(4.0, 28.0);
    return pw.Container(
      decoration: _cardDecoration(node.isFocus),
      padding: pw.EdgeInsets.symmetric(horizontal: pad + 1, vertical: pad),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Container(
            width: avatarSize,
            height: avatarSize,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _tintFor(p.sex),
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              _initials(p),
              style: pw.TextStyle(
                font: bodyBold,
                fontFallback: fallback,
                fontSize: _scaled(13, fit),
                color: _paper,
              ),
            ),
          ),
          pw.SizedBox(width: _scaled(6, fit, min: 2)),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Text(
                  p.fullName,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: bodyBold,
                    fontFallback: fallback,
                    fontSize: _scaled(11, fit),
                    color: _ink,
                  ),
                ),
                pw.Text(
                  _yearSpan(p),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: body,
                    fontFallback: fallback,
                    fontSize: _scaled(9.5, fit),
                    color: _muted,
                  ),
                ),
                if ((p.code ?? '').isNotEmpty)
                  pw.Text(
                    p.code!,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: body,
                      fontFallback: fallback,
                      fontSize: _scaled(8, fit),
                      color: _muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

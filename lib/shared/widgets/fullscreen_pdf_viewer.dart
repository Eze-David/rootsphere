import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_colors.dart';

/// Opens [reference] (a network URL or, on non-web platforms, a local file
/// path) as an in-app PDF viewer, so tapping a PDF attachment never has to
/// leave the app for a browser or external reader.
Future<void> showFullscreenPdf(
  BuildContext context, {
  required String reference,
  String? title,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _FullscreenPdfViewer(reference: reference, title: title),
    ),
  );
}

bool _isNetwork(String reference) =>
    reference.startsWith('http') || reference.startsWith('blob:');

class _FullscreenPdfViewer extends StatelessWidget {
  const _FullscreenPdfViewer({required this.reference, this.title});
  final String reference;
  final String? title;

  Future<Uint8List> _load(PdfPageFormat format) async {
    if (_isNetwork(reference)) {
      final res = await http.get(Uri.parse(reference));
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }
      return res.bodyBytes;
    }
    if (kIsWeb) {
      throw Exception('Local files are not available on web.');
    }
    return File(reference).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Document')),
      backgroundColor: AppColors.surfaceMuted,
      body: PdfPreview(
        build: _load,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

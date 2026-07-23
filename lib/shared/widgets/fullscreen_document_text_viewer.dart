import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/records/data/services/ocr_service.dart';

/// Opens [url] (a non-image, non-PDF document — e.g. .docx) as an in-app text
/// preview, so tapping it never has to leave the app for a browser or
/// external reader. Reuses the `ocr` edge function's direct .docx extraction;
/// other formats it can't read simply show a friendly "not supported" note.
Future<void> showFullscreenDocumentText(
  BuildContext context, {
  required String url,
  String? title,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _FullscreenDocumentTextViewer(url: url, title: title),
    ),
  );
}

class _FullscreenDocumentTextViewer extends StatefulWidget {
  const _FullscreenDocumentTextViewer({required this.url, this.title});
  final String url;
  final String? title;

  @override
  State<_FullscreenDocumentTextViewer> createState() =>
      _FullscreenDocumentTextViewerState();
}

class _FullscreenDocumentTextViewerState
    extends State<_FullscreenDocumentTextViewer> {
  late final Future<OcrResult> _future = OcrService().extractText(
    fileUrl: widget.url,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Document')),
      backgroundColor: AppColors.surfaceMuted,
      body: FutureBuilder<OcrResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final OcrResult? result = snapshot.data;
          if (result == null || !result.hasText) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  result?.message ??
                      'Preview isn\'t available for this file type.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SelectableText(
              result.text!.trim(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        },
      ),
    );
  }
}

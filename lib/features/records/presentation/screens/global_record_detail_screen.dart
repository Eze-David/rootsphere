import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../../../shared/widgets/fullscreen_document_text_viewer.dart';
import '../../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../../shared/widgets/fullscreen_pdf_viewer.dart';
import '../../domain/entities/global_record_match.dart';
import '../../domain/entities/record.dart';

/// Read-only detail view for a community (cross-tree, unattached) record —
/// what "View" opens instead of handing the raw file straight to the
/// browser, which just downloads non-renderable types like .docx instead of
/// showing anything useful. Mirrors [RecordDetailScreen]'s layout (hero,
/// citation, extracted text) but nothing here is editable: it isn't this
/// viewer's record until they tap "Save to my records".
class GlobalRecordDetailScreen extends StatelessWidget {
  const GlobalRecordDetailScreen({
    super.key,
    required this.match,
    required this.saved,
    required this.onSave,
  });

  final GlobalRecordMatch match;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasOcrText = (match.ocrText ?? '').trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(match.type.label)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          _Attachment(match: match),
          const SizedBox(height: AppSpacing.lg),
          Text(match.displayTitle, style: text.headlineSmall),
          if (match.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(match.subtitle, style: text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text('CITATION', style: text.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(match.citation, style: text.bodyMedium),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: match.citation),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Citation copied.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
          ),
          if (hasOcrText) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            Text('EXTRACTED TEXT', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SelectableText(
                match.ocrText!.trim(),
                style: text.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saved
                  ? null
                  : () {
                      onSave();
                      Navigator.of(context).pop();
                    },
              icon: Icon(saved ? Icons.check : Icons.add),
              label: Text(saved ? 'Saved' : 'Save to my records'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.match});
  final GlobalRecordMatch match;

  @override
  Widget build(BuildContext context) {
    if (match.hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: GestureDetector(
          onTap: () => showFullscreenImage(context, match.fileUrl!),
          child: AdaptiveImage(
            reference: match.fileUrl!,
            width: double.infinity,
            height: 240,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final TextTheme text = Theme.of(context).textTheme;
    final bool hasFile = match.fileUrl != null;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            match.mediaKind == RecordMediaKind.pdf
                ? Icons.picture_as_pdf_outlined
                : match.type.icon,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            match.fileName ?? 'No attachment',
            style: text.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasFile) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => match.mediaKind == RecordMediaKind.pdf
                  ? showFullscreenPdf(
                      context,
                      reference: match.fileUrl!,
                      title: match.displayTitle,
                    )
                  : showFullscreenDocumentText(
                      context,
                      url: match.fileUrl!,
                      title: match.displayTitle,
                    ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                match.mediaKind == RecordMediaKind.pdf
                    ? 'View PDF'
                    : 'Open file',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../../../shared/widgets/fullscreen_document_text_viewer.dart';
import '../../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../../shared/widgets/fullscreen_pdf_viewer.dart';
import '../../../assistant/domain/entities/assistant_result.dart';
import '../../../assistant/presentation/providers/assistant_providers.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../domain/entities/record.dart';
import '../providers/record_providers.dart';
import '../widgets/record_upload_sheet.dart';

/// Full-screen view of a single record: attachment preview, structured details,
/// citation builder, extracted (OCR) text, and linked people.
class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Record? record = ref.watch(recordByIdProvider(recordId));

    if (record == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Record not found.')),
      );
    }

    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(record.type.label),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () =>
                showRecordUploadSheet(context, ref, existing: record),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref, record),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          _Attachment(record: record),
          const SizedBox(height: AppSpacing.lg),
          Text(record.displayTitle, style: text.headlineSmall),
          if (record.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(record.subtitle, style: text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xl),
          _CitationSection(record: record),
          const SizedBox(height: AppSpacing.xl),
          _OcrSection(record: record),
          const SizedBox(height: AppSpacing.xl),
          _AssistantSection(record: record),
          const SizedBox(height: AppSpacing.xl),
          _LinkedPeopleSection(record: record),
          if ((record.notes ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            Text('NOTES', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(record.notes!.trim(), style: text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Record record,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text(
          'This permanently removes the record and its file.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (record.fileUrl != null) {
      await ref
          .read(recordStorageServiceProvider)
          .deleteRecordFile(record.fileUrl!);
    }
    await ref
        .read(recordRepositoryProvider)
        .deleteRecord(record.treeId, record.id);
    if (context.mounted) context.pop();
  }
}

// ── Attachment preview ───────────────────────────────────────────────────────

class _Attachment extends StatelessWidget {
  const _Attachment({required this.record});
  final Record record;

  @override
  Widget build(BuildContext context) {
    if (record.hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: GestureDetector(
          onTap: () => showFullscreenImage(context, record.fileUrl!),
          child: AdaptiveImage(
            reference: record.fileUrl!,
            width: double.infinity,
            height: 240,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final TextTheme text = Theme.of(context).textTheme;
    final bool hasFile = record.fileUrl != null;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            record.mediaKind == RecordMediaKind.pdf
                ? Icons.picture_as_pdf_outlined
                : record.type.icon,
            size: 48,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            record.fileName ?? 'No attachment',
            style: text.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasFile) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => record.mediaKind == RecordMediaKind.pdf
                  ? showFullscreenPdf(
                      context,
                      reference: record.fileUrl!,
                      title: record.displayTitle,
                    )
                  : showFullscreenDocumentText(
                      context,
                      url: record.fileUrl!,
                      title: record.displayTitle,
                    ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                record.mediaKind == RecordMediaKind.pdf
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

// ── Citation ─────────────────────────────────────────────────────────────────

class _CitationSection extends ConsumerWidget {
  const _CitationSection({required this.record});
  final Record record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('CITATION', style: text.labelSmall)),
            TextButton.icon(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(record.citation, style: text.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: record.citation),
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
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: record.citation);
    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit citation'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Citation text',
            alignLabelWithHint: true,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await ref
        .read(recordRepositoryProvider)
        .upsertRecord(
          record.copyWith(citationOverride: result.isEmpty ? null : result),
        );
  }
}

// ── OCR ──────────────────────────────────────────────────────────────────────

class _OcrSection extends ConsumerStatefulWidget {
  const _OcrSection({required this.record});
  final Record record;

  @override
  ConsumerState<_OcrSection> createState() => _OcrSectionState();
}

class _OcrSectionState extends ConsumerState<_OcrSection> {
  bool _running = false;
  String? _message;

  Future<void> _run() async {
    final String? url = widget.record.fileUrl;
    if (url == null) return;
    setState(() {
      _running = true;
      _message = null;
    });
    final ocr = await ref.read(ocrServiceProvider).extractText(fileUrl: url);
    if (ocr.hasText) {
      await ref
          .read(recordRepositoryProvider)
          .upsertRecord(widget.record.copyWith(ocrText: ocr.text));
    }
    if (mounted) {
      setState(() {
        _running = false;
        _message = ocr.hasText
            ? null
            : (ocr.message ?? 'No text found in this document.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Record record = widget.record;
    final bool hasText = (record.ocrText ?? '').trim().isNotEmpty;
    final bool canRun = record.canExtractText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('EXTRACTED TEXT', style: text.labelSmall)),
            if (canRun)
              TextButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined, size: 16),
                label: Text(hasText ? 'Re-run OCR' : 'Run OCR'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasText)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              record.ocrText!.trim(),
              style: text.bodyMedium,
            ),
          )
        else
          Text(
            _message ?? 'No text extracted yet.',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

// ── AI Assistant ─────────────────────────────────────────────────────────────

class _AssistantSection extends ConsumerStatefulWidget {
  const _AssistantSection({required this.record});
  final Record record;

  @override
  ConsumerState<_AssistantSection> createState() => _AssistantSectionState();
}

class _AssistantSectionState extends ConsumerState<_AssistantSection> {
  String? _runningAction;
  String? _message;
  String _targetLanguage = 'English';

  Record get _record => widget.record;
  String get _sourceText => (_record.ocrText ?? _record.notes ?? '').trim();

  Future<void> _run(String action, Future<void> Function() body) async {
    setState(() {
      _runningAction = action;
      _message = null;
    });
    await body();
    if (mounted) setState(() => _runningAction = null);
  }

  Future<void> _summarize() => _run('summarize', () async {
    final res = await ref
        .read(assistantServiceProvider)
        .summarize(scope: _record.id, text: _sourceText);
    await _apply(res, (r) => r.copyWith(aiSummary: res.data));
  });

  Future<void> _translate() => _run('translate', () async {
    final res = await ref
        .read(assistantServiceProvider)
        .translate(
          scope: _record.id,
          text: _sourceText,
          targetLanguage: _targetLanguage,
        );
    await _apply(
      res,
      (r) => r.copyWith(
        aiTranslation: res.data,
        aiTranslationLang: _targetLanguage,
      ),
    );
  });

  Future<void> _identifyLocations() => _run('locations', () async {
    final res = await ref
        .read(assistantServiceProvider)
        .identifyLocations(scope: _record.id, text: _sourceText);
    await _apply(res, (r) => r.copyWith(aiLocations: res.data));
  });

  Future<void> _transcribeHandwriting() => _run('transcribe', () async {
    final res = await ref
        .read(assistantServiceProvider)
        .transcribeHandwriting(scope: _record.id, fileUrl: _record.fileUrl!);
    await _apply(res, (r) => r.copyWith(ocrText: res.data));
  });

  Future<void> _pickTargetLanguage() async {
    final controller = TextEditingController(text: _targetLanguage);
    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Translate to'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. French, Igbo, Yoruba',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _targetLanguage = result);
    }
  }

  Future<void> _apply<T>(
    AssistantResponse<T> res,
    Record Function(Record) withResult,
  ) async {
    if (res.available && res.hasData) {
      await ref
          .read(recordRepositoryProvider)
          .upsertRecord(withResult(_record));
    }
    if (mounted) {
      setState(() => _message = res.available ? null : res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Record record = _record;
    final bool hasText = _sourceText.isNotEmpty;
    final bool hasImage = record.hasImage;
    final bool busy = _runningAction != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('AI ASSISTANT', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            _AssistantChip(
              label: (record.aiSummary ?? '').trim().isEmpty
                  ? 'Summarize'
                  : 'Re-summarize',
              icon: Icons.summarize_outlined,
              loading: _runningAction == 'summarize',
              onPressed: (!busy && hasText) ? _summarize : null,
            ),
            _AssistantChip(
              label: (record.aiTranslation ?? '').trim().isEmpty
                  ? 'Translate to $_targetLanguage'
                  : 'Re-translate to $_targetLanguage',
              icon: Icons.translate_outlined,
              loading: _runningAction == 'translate',
              onPressed: (!busy && hasText) ? _translate : null,
            ),
            if (hasText)
              ActionChip(
                avatar: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Change language'),
                onPressed: busy ? null : _pickTargetLanguage,
              ),
            _AssistantChip(
              label: 'Identify locations',
              icon: Icons.place_outlined,
              loading: _runningAction == 'locations',
              onPressed: (!busy && hasText) ? _identifyLocations : null,
            ),
            _AssistantChip(
              label: 'Transcribe handwriting',
              icon: Icons.draw_outlined,
              loading: _runningAction == 'transcribe',
              onPressed: (!busy && hasImage) ? _transcribeHandwriting : null,
            ),
          ],
        ),
        if (!hasText && !hasImage) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Run OCR or add notes first so the assistant has text to work with.',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (_message != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _message!,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if ((record.aiSummary ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _AssistantResultCard(
            label: 'Summary',
            body: record.aiSummary!.trim(),
          ),
        ],
        if ((record.aiTranslation ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _AssistantResultCard(
            label:
                'Translation'
                '${(record.aiTranslationLang ?? '').isEmpty ? '' : ' (${record.aiTranslationLang})'}',
            body: record.aiTranslation!.trim(),
          ),
        ],
        if (record.aiLocations.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text('LOCATIONS FOUND', style: text.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final loc in record.aiLocations)
                Chip(
                  label: Text(loc),
                  avatar: const Icon(Icons.place_outlined, size: 16),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AssistantChip extends StatelessWidget {
  const _AssistantChip({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _AssistantResultCard extends StatelessWidget {
  const _AssistantResultCard({required this.label, required this.body});
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label.toUpperCase(), style: text.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(body, style: text.bodyMedium),
        ],
      ),
    );
  }
}

// ── Linked people ─────────────────────────────────────────────────────────────

class _LinkedPeopleSection extends ConsumerWidget {
  const _LinkedPeopleSection({required this.record});
  final Record record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final Map<String, Person> people = ref.watch(personMapProvider);
    final List<Person> linked = record.personIds
        .map((id) => people[id])
        .whereType<Person>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('LINKED PEOPLE', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        if (linked.isEmpty)
          Text(
            'No people linked to this record.',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final Person p in linked)
                ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(p.fullName),
                  onPressed: () => context.push('${AppRoutes.person}/${p.id}'),
                ),
            ],
          ),
      ],
    );
  }
}

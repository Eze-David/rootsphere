import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/fullscreen_document_text_viewer.dart';
import '../../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../../shared/widgets/fullscreen_pdf_viewer.dart';
import '../../../collab/presentation/providers/role_verification_providers.dart';
import '../../../records/domain/entities/record.dart' as personal;
import '../../../records/presentation/providers/record_providers.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../../tree/presentation/widgets/audio_player_sheet.dart';
import '../../../tree/presentation/widgets/video_player_screen.dart';
import '../../domain/entities/archive_access_request.dart';
import '../../domain/entities/archive_record.dart';
import '../providers/archive_providers.dart';

const Set<String> _imageExtensions = <String>{
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'tif', 'tiff',
};
const Set<String> _videoExtensions = <String>{'mp4', 'm4v', 'mov'};
const Set<String> _audioExtensions = <String>{'mp3', 'm4a', 'wav'};

String _extensionOf(String name) {
  final int dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// What the sheet was dismissed for, so the caller (which has access to the
/// hosting screen's own context/ancestors — the sheet itself doesn't, since
/// a modal route sits outside the calling widget's local InheritedWidgets
/// like DefaultTabController) can act on it after the sheet closes.
enum ArchiveDetailAction { continueEditing }

/// Shared record-detail view for both the admin Stored-collections tab and
/// the public Catalogue browser — actions shown differ by admin/tier.
Future<ArchiveDetailAction?> showArchiveRecordDetail(
  BuildContext context,
  WidgetRef ref,
  ArchiveRecord record,
) {
  return showModalBottomSheet<ArchiveDetailAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _ArchiveRecordDetailSheet(record: record),
  );
}

class _ArchiveRecordDetailSheet extends ConsumerStatefulWidget {
  const _ArchiveRecordDetailSheet({required this.record});
  final ArchiveRecord record;

  @override
  ConsumerState<_ArchiveRecordDetailSheet> createState() =>
      _ArchiveRecordDetailSheetState();
}

class _ArchiveRecordDetailSheetState
    extends ConsumerState<_ArchiveRecordDetailSheet> {
  bool _busy = false;

  String get _format {
    final Set<String> exts = widget.record.files
        .map((f) => _extensionOf(f.fileName))
        .toSet();
    final List<String> parts = <String>[
      if (exts.any(_imageExtensions.contains)) 'image scans',
      if (exts.contains('pdf')) 'PDF documents',
      if (exts.any(_videoExtensions.contains)) 'video recordings',
      if (exts.any(_audioExtensions.contains)) 'audio recordings',
    ];
    if (parts.isEmpty) {
      return widget.record.accessStatus == ArchiveAccessStatus.archive
          ? 'Catalogued, not yet digitized'
          : 'No files attached yet';
    }
    return parts.join(' + ');
  }

  Future<void> _openFile(ArchiveFile file) async {
    final String ext = _extensionOf(
      file.fileName.isNotEmpty ? file.fileName : file.url,
    );
    if (_imageExtensions.contains(ext)) {
      await showFullscreenImage(context, file.url);
    } else if (ext == 'pdf') {
      await showFullscreenPdf(context, reference: file.url, title: file.fileName);
    } else if (_videoExtensions.contains(ext)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(reference: file.url),
        ),
      );
    } else if (_audioExtensions.contains(ext)) {
      await showAudioPlayerSheet(context, reference: file.url);
    } else {
      await showFullscreenDocumentText(context, url: file.url, title: file.fileName);
    }
  }

  /// Opens the single attachment directly, or a picker sheet when there's
  /// more than one — the mockup's "Browse images" is one button regardless
  /// of how many files a record has.
  Future<void> _openFiles(List<ArchiveFile> files) async {
    if (files.length == 1) {
      await _openFile(files.first);
      return;
    }
    final ArchiveFile? chosen = await showModalBottomSheet<ArchiveFile>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FilePickerSheet(files: files),
    );
    if (chosen != null) await _openFile(chosen);
  }

  Future<void> _requestAccess() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(archiveAccessRequestRepositoryProvider)
          .request(widget.record.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access requested — an admin will review it.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSaved(bool saved) async {
    final repo = ref.read(savedArchiveRecordsRepositoryProvider);
    if (saved) {
      await repo.unsave(widget.record.id);
    } else {
      await repo.save(widget.record.id);
    }
  }

  Future<void> _attachToTree() async {
    final List<Person> persons = ref.read(personsProvider).value ?? const <Person>[];
    if (persons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add someone to your tree first.')),
      );
      return;
    }
    final Person? chosen = await showModalBottomSheet<Person>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PersonPickerSheet(persons: persons),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final String treeId = ref.read(activeTreeIdProvider);
      final ArchiveRecord r = widget.record;
      final personal.Record record = personal.Record(
        id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
        treeId: treeId,
        type: r.type,
        title: r.displayTitle,
        repository: r.repositorySource,
        date: r.dateRangeStart != null ? DateTime(r.dateRangeStart!) : null,
        fileUrl: r.files.isEmpty ? null : r.files.first.url,
        fileName: r.files.isEmpty ? null : r.files.first.fileName,
        citationOverride: r.recordRef == null
            ? null
            : '${r.title.isEmpty ? r.type.cardPrefix : r.title} (${r.recordRef}), Rootsphere Digital Records Repository.',
        personIds: <String>[chosen.id],
        createdAt: DateTime.now(),
      );
      await ref.read(recordRepositoryProvider).upsertRecord(record);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Attached to ${chosen.fullName}.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ArchiveRecord r = widget.record;
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;
    final bool saved = ref.watch(isArchiveRecordSavedProvider(r.id));
    final ArchiveAccessRequest? myRequest = isAdmin
        ? null
        : ref.watch(archiveAccessRequestForRecordProvider(r.id));

    final bool canBrowse =
        r.files.isNotEmpty &&
        (isAdmin || r.accessStatus == ArchiveAccessStatus.online);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: <Widget>[
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              alignment: Alignment.center,
              child: Icon(
                r.type.icon,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              r.displayTitle,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (r.collection.isNotEmpty || r.files.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                <String>[
                  if (r.collection.isNotEmpty) r.collection,
                  '${r.files.length} image${r.files.length == 1 ? '' : 's'}',
                ].join(' · '),
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _DetailRow(label: 'Reference', value: r.recordRef ?? 'Not yet assigned'),
            _DetailRow(label: 'Access', value: r.accessStatus.label),
            _DetailRow(label: 'Format', value: _format),
            const _DetailRow(
              label: 'Rights',
              value: 'View according to repository permission',
            ),
            if ((r.description ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(r.description!, style: text.bodyMedium),
            ],
            if (r.keywords.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final String k in r.keywords) Chip(label: Text(k)),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            // ── Three full-width stacked actions, matching the mockup ────
            SizedBox(
              width: double.infinity,
              child: canBrowse
                  ? FilledButton.icon(
                      onPressed: () => _openFiles(r.files),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Browse images'),
                    )
                  : !isAdmin && r.accessStatus == ArchiveAccessStatus.permission
                  ? _PermissionCta(
                      request: myRequest,
                      busy: _busy,
                      onRequest: _requestAccess,
                    )
                  : FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.image_not_supported_outlined),
                      label: Text(
                        r.files.isEmpty ? 'No files attached yet' : 'Not digitized yet',
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _toggleSaved(saved),
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                label: Text(saved ? 'Saved' : 'Save collection'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _attachToTree,
                icon: const Icon(Icons.family_restroom_outlined),
                label: const Text('Attach to family tree'),
              ),
            ),
            if (isAdmin &&
                (r.reviewStatus == ArchiveReviewStatus.draft ||
                    r.reviewStatus == ArchiveReviewStatus.rejected)) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(ArchiveDetailAction.continueEditing),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Continue editing'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PermissionCta extends StatelessWidget {
  const _PermissionCta({
    required this.request,
    required this.busy,
    required this.onRequest,
  });

  final ArchiveAccessRequest? request;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    if (request?.status == ArchiveAccessRequestStatus.pending) {
      return const _StatusPill(
        icon: Icons.hourglass_top_outlined,
        label: 'Access request pending',
      );
    }
    final bool wasRejected = request?.status == ArchiveAccessRequestStatus.rejected;
    return FilledButton.icon(
      onPressed: busy ? null : onRequest,
      icon: const Icon(Icons.lock_open_outlined),
      label: Text(wasRejected ? 'Request access again' : 'Request access'),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 90,
            child: Text(label, style: text.bodySmall?.copyWith(color: AppColors.textTertiary)),
          ),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

class _FilePickerSheet extends StatelessWidget {
  const _FilePickerSheet({required this.files});
  final List<ArchiveFile> files;

  IconData _iconFor(ArchiveFile f) {
    final String ext = _extensionOf(f.fileName);
    if (_imageExtensions.contains(ext)) return Icons.image_outlined;
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (_videoExtensions.contains(ext)) return Icons.videocam_outlined;
    if (_audioExtensions.contains(ext)) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Text('Files', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          for (final ArchiveFile f in files)
            ListTile(
              leading: Icon(_iconFor(f)),
              title: Text(f.fileName.isEmpty ? 'File' : f.fileName),
              onTap: () => Navigator.of(context).pop(f),
            ),
        ],
      ),
    );
  }
}

class _PersonPickerSheet extends StatelessWidget {
  const _PersonPickerSheet({required this.persons});
  final List<Person> persons;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Text('Attach to', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          for (final Person p in persons)
            ListTile(
              title: Text(p.fullName),
              onTap: () => Navigator.of(context).pop(p),
            ),
        ],
      ),
    );
  }
}

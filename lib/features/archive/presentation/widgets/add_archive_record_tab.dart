import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../records/domain/entities/record.dart';
import '../../domain/entities/archive_record.dart';
import '../providers/archive_providers.dart';

const List<String> _allowedExtensions = <String>[
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'tif',
  'tiff',
  'mp3',
  'mp4',
  'wav',
  'm4a',
  'mov',
];

class _PendingFile {
  _PendingFile(this.file, this.kind);
  final PlatformFile file;
  ArchiveFileKind kind;
}

/// Steps 1–2 of the mockup ("Upload" + "Describe") collapsed into one
/// scrolling form — the fields stay visible while scrolling rather than
/// being split behind forced Next/Back navigation, which matches how the
/// mockup actually behaves (every field is reachable on one screen).
class AddArchiveRecordTab extends ConsumerStatefulWidget {
  const AddArchiveRecordTab({super.key});

  @override
  ConsumerState<AddArchiveRecordTab> createState() =>
      _AddArchiveRecordTabState();
}

class _AddArchiveRecordTabState extends ConsumerState<AddArchiveRecordTab> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _collection = TextEditingController();
  final _country = TextEditingController();
  final _stateRegion = TextEditingController();
  final _locality = TextEditingController();
  final _dateStart = TextEditingController();
  final _dateEnd = TextEditingController();
  final _repositorySource = TextEditingController();
  final _contributor = TextEditingController();
  final _keywords = TextEditingController();
  final _description = TextEditingController();

  RecordType _type = RecordType.birth;
  final List<_PendingFile> _pendingFiles = <_PendingFile>[];
  List<ArchiveFile> _existingFiles = <ArchiveFile>[];
  ArchiveAccessStatus _accessStatus = ArchiveAccessStatus.archive;
  bool _accessManuallySet = false;
  bool _saving = false;
  String? _statusMessage;

  /// The record loaded from Stored collections for editing, or null when
  /// this form is building a brand-new record. Kept so Save/Submit can
  /// preserve fields the form doesn't expose (id, recordRef, reviewStatus,
  /// createdAt/By, reviewer fields) via [ArchiveRecord.copyWith].
  ArchiveRecord? _editingSnapshot;

  @override
  void initState() {
    super.initState();
    // ref.listen (registered in build) only reacts to *future* changes — if
    // a record was already selected for editing before this State was
    // (re)created (e.g. this tab got rebuilt after navigating away and
    // back), that value would otherwise be missed and the form would open
    // blank. Field assignment here (no setState) is picked up by the first
    // build automatically.
    final ArchiveRecord? current = ref.read(archiveRecordBeingEditedProvider);
    if (current != null) _applyRecord(current);
  }

  @override
  void dispose() {
    _title.dispose();
    _collection.dispose();
    _country.dispose();
    _stateRegion.dispose();
    _locality.dispose();
    _dateStart.dispose();
    _dateEnd.dispose();
    _repositorySource.dispose();
    _contributor.dispose();
    _keywords.dispose();
    _description.dispose();
    super.dispose();
  }

  List<String> get _keywordList => _keywords.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String get _searchTextPreview => <String>[
    _title.text.trim(),
    _collection.text.trim(),
    _description.text.trim(),
    ..._keywordList,
  ].where((s) => s.isNotEmpty).join(' · ');

  Future<void> _pickFiles() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      final bool hadNoFiles = _existingFiles.isEmpty && _pendingFiles.isEmpty;
      for (final PlatformFile f in result.files) {
        _pendingFiles.add(
          _PendingFile(
            f,
            _pendingFiles.isEmpty
                ? ArchiveFileKind.master
                : ArchiveFileKind.supporting,
          ),
        );
      }
      // Attaching the first file is a reasonable signal this record is meant
      // to be viewable, not just a catalogue pointer — but only nudge the
      // default if the admin hasn't already picked an access level themselves.
      if (hadNoFiles && !_accessManuallySet) {
        _accessStatus = ArchiveAccessStatus.online;
      }
    });
  }

  void _removeFile(_PendingFile f) => setState(() => _pendingFiles.remove(f));

  /// Populates every field/controller from [r]. No setState — safe to call
  /// from initState (before the first build) as well as from
  /// [_loadForEditing] (after the widget is already mounted).
  void _applyRecord(ArchiveRecord r) {
    _title.text = r.title;
    _collection.text = r.collection;
    _country.text = r.country;
    _stateRegion.text = r.stateRegion;
    _locality.text = r.locality;
    _dateStart.text = r.dateRangeStart?.toString() ?? '';
    _dateEnd.text = r.dateRangeEnd?.toString() ?? '';
    _repositorySource.text = r.repositorySource;
    _contributor.text = r.contributor;
    _keywords.text = r.keywords.join(', ');
    _description.text = r.description ?? '';
    _editingSnapshot = r;
    _type = r.type;
    _existingFiles = List<ArchiveFile>.of(r.files);
    _pendingFiles.clear();
    _accessStatus = r.accessStatus;
    _accessManuallySet = true;
    _statusMessage = null;
  }

  /// Populates the form from [r] so an admin can continue a saved draft (or
  /// revise a rejected record) instead of only ever starting from scratch.
  /// Called once this widget is already mounted (see [initState] for the
  /// pre-mount case) — wraps [_applyRecord] in setState to trigger a rebuild.
  void _loadForEditing(ArchiveRecord r) => setState(() => _applyRecord(r));

  void _resetForm() {
    _formKey.currentState?.reset();
    _title.clear();
    _collection.clear();
    _country.clear();
    _stateRegion.clear();
    _locality.clear();
    _dateStart.clear();
    _dateEnd.clear();
    _repositorySource.clear();
    _contributor.clear();
    _keywords.clear();
    _description.clear();
    setState(() {
      _type = RecordType.birth;
      _pendingFiles.clear();
      _existingFiles = <ArchiveFile>[];
      _accessStatus = ArchiveAccessStatus.archive;
      _accessManuallySet = false;
      _editingSnapshot = null;
      _statusMessage = null;
    });
    ref.read(archiveRecordBeingEditedProvider.notifier).state = null;
  }

  Future<void> _save({required bool submitForReview}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _statusMessage = null;
    });

    try {
      final ArchiveRecord? editing = _editingSnapshot;
      final String id =
          editing?.id ?? 'arc_${DateTime.now().microsecondsSinceEpoch}';
      final List<ArchiveFile> uploaded = <ArchiveFile>[];

      if (_pendingFiles.isNotEmpty) {
        final service = ref.read(archiveStorageServiceProvider);
        for (int i = 0; i < _pendingFiles.length; i++) {
          final _PendingFile pf = _pendingFiles[i];
          final bytes = pf.file.bytes;
          if (bytes == null) {
            throw const ServerFailure('Could not read a selected file.');
          }
          setState(
            () => _statusMessage =
                'Uploading ${i + 1} of ${_pendingFiles.length}…',
          );
          final stored = await service.uploadArchiveFile(
            recordId: id,
            fileName: pf.file.name,
            bytes: bytes,
          );
          uploaded.add(
            ArchiveFile(url: stored.url, fileName: stored.fileName, kind: pf.kind),
          );
        }
      }

      // copyWith on the existing record preserves fields this form doesn't
      // expose (recordRef, reviewStatus, createdAt/By, reviewer fields) —
      // editing a draft/rejected record and hitting "Save draft" must not
      // silently wipe those out.
      final ArchiveRecord record = (editing ?? ArchiveRecord(id: id)).copyWith(
        title: _title.text.trim(),
        type: _type,
        collection: _collection.text.trim(),
        country: _country.text.trim(),
        stateRegion: _stateRegion.text.trim(),
        locality: _locality.text.trim(),
        dateRangeStart: int.tryParse(_dateStart.text.trim()),
        dateRangeEnd: int.tryParse(_dateEnd.text.trim()),
        repositorySource: _repositorySource.text.trim(),
        contributor: _contributor.text.trim(),
        keywords: _keywordList,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        files: <ArchiveFile>[..._existingFiles, ...uploaded],
        searchText: _searchTextPreview.isEmpty ? null : _searchTextPreview,
        accessStatus: _accessStatus,
      );

      await ref.read(archiveRepositoryProvider).upsertRecord(record);
      if (submitForReview) {
        setState(() => _statusMessage = 'Submitting for review…');
        await ref.read(archiveRepositoryProvider).submitForReview(id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submitForReview ? 'Submitted for review.' : 'Saved as draft.',
          ),
        ),
      );
      _resetForm();
      DefaultTabController.of(
        context,
      ).animateTo(submitForReview ? 1 : 2); // Review queue / Stored collections
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = e is Failure ? e.message : 'Could not save the record.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // Reacts only when a *different* record is selected on Stored
    // collections (reference equality), so it won't stomp on in-progress
    // edits just because the underlying records stream re-emits.
    ref.listen<ArchiveRecord?>(archiveRecordBeingEditedProvider, (
      previous,
      next,
    ) {
      if (next != null && !identical(previous, next)) _loadForEditing(next);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_editingSnapshot != null) ...<Widget>[
              _EditingBanner(
                record: _editingSnapshot!,
                onDiscard: _saving ? null : _resetForm,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('Record details', style: text.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _title,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Record title',
                      hintText: 'e.g. Birth Register — Kwande District, 1952–1964',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Add a record title.'
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<RecordType>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Record type'),
                    items: RecordType.values
                        .map(
                          (t) => DropdownMenuItem<RecordType>(
                            value: t,
                            child: Text(t.label, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (t) {
                            if (t != null) setState(() => _type = t);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _collection,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Collection',
                      hintText: 'e.g. Benue State Civil Records',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<ArchiveAccessStatus>(
                    initialValue: _accessStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Access level'),
                    items: ArchiveAccessStatus.values
                        .map(
                          (a) => DropdownMenuItem<ArchiveAccessStatus>(
                            value: a,
                            child: Text(a.label),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (a) {
                            if (a != null) {
                              setState(() {
                                _accessStatus = a;
                                _accessManuallySet = true;
                              });
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _country,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _stateRegion,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'State / region'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _locality,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Locality'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _dateStart,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'From year'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          controller: _dateEnd,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'To year'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _repositorySource,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Repository or source',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _contributor,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Contributor'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _keywords,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Names and keywords',
                hintText: 'Comma-separated, e.g. births, Kwande, civil registration',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _description,
              enabled: !_saving,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            _FilesPicker(
              existingFiles: _existingFiles,
              pendingFiles: _pendingFiles,
              onAdd: _saving ? null : _pickFiles,
              onRemoveExisting: _saving
                  ? null
                  : (f) => setState(() => _existingFiles.remove(f)),
              onRemovePending: _saving ? null : _removeFile,
              onKindChanged: _saving
                  ? null
                  : (f, kind) => setState(() => f.kind = kind),
            ),
            const SizedBox(height: AppSpacing.lg),
            _CataloguePreview(
              recordRef: _editingSnapshot?.recordRef,
              accessStatus: _accessStatus,
              fileCount: _existingFiles.length + _pendingFiles.length,
              searchText: _searchTextPreview,
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                'Preservation rule: never overwrite the original scan. '
                'Corrections belong in the searchable transcription and '
                'catalogue description.',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            if (_statusMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _statusMessage!,
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(submitForReview: false),
                    child: const Text('Save draft'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(submitForReview: true),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text('Submit for review'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _FilesPicker extends StatelessWidget {
  const _FilesPicker({
    required this.existingFiles,
    required this.pendingFiles,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemovePending,
    required this.onKindChanged,
  });

  final List<ArchiveFile> existingFiles;
  final List<_PendingFile> pendingFiles;
  final VoidCallback? onAdd;
  final ValueChanged<ArchiveFile>? onRemoveExisting;
  final ValueChanged<_PendingFile>? onRemovePending;
  final void Function(_PendingFile, ArchiveFileKind)? onKindChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Files', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              color: theme.colorScheme.surface,
            ),
            child: Column(
              children: <Widget>[
                const Icon(Icons.upload_file, color: AppColors.primary),
                const SizedBox(height: AppSpacing.xs),
                Text('Upload scanned pages, photographs, audio or video', style: text.bodyMedium),
                Text(
                  'PDF, JPG, PNG, TIFF, MP3 or MP4',
                  style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
        if (existingFiles.isNotEmpty || pendingFiles.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          for (final ArchiveFile f in existingFiles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.check_circle_outline, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      f.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                  Text(
                    f.kind == ArchiveFileKind.master ? 'Master scan' : 'Supporting',
                    style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onRemoveExisting == null
                        ? null
                        : () => onRemoveExisting!(f),
                  ),
                ],
              ),
            ),
          for (final _PendingFile f in pendingFiles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.insert_drive_file_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      f.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                  DropdownButton<ArchiveFileKind>(
                    value: f.kind,
                    isDense: true,
                    items: ArchiveFileKind.values
                        .map(
                          (k) => DropdownMenuItem<ArchiveFileKind>(
                            value: k,
                            child: Text(k == ArchiveFileKind.master ? 'Master scan' : 'Supporting'),
                          ),
                        )
                        .toList(),
                    onChanged: onKindChanged == null
                        ? null
                        : (k) {
                            if (k != null) onKindChanged!(f, k);
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onRemovePending == null
                        ? null
                        : () => onRemovePending!(f),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _CataloguePreview extends StatelessWidget {
  const _CataloguePreview({
    required this.recordRef,
    required this.accessStatus,
    required this.fileCount,
    required this.searchText,
  });

  final String? recordRef;
  final ArchiveAccessStatus accessStatus;
  final int fileCount;
  final String searchText;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Catalogue preview', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          _PreviewRow(
            label: 'Record ID',
            value: recordRef ?? 'Assigned when submitted for review',
          ),
          _PreviewRow(label: 'Access', value: accessStatus.label),
          _PreviewRow(label: 'Files', value: fileCount == 0 ? 'None yet' : '$fileCount file${fileCount == 1 ? '' : 's'}'),
          _PreviewRow(
            label: 'Search text',
            value: searchText.isEmpty ? 'Fill in the fields above' : searchText,
          ),
        ],
      ),
    );
  }
}

class _EditingBanner extends StatelessWidget {
  const _EditingBanner({required this.record, required this.onDiscard});

  final ArchiveRecord record;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.edit_outlined, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Editing "${record.displayTitle}" (${record.reviewStatus.label})',
              style: text.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            child: const Text('New record'),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});
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
          Expanded(child: Text(value, style: text.bodySmall)),
        ],
      ),
    );
  }
}

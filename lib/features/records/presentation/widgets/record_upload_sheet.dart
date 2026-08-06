import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../domain/entities/record.dart';
import '../providers/record_providers.dart';

/// Opens the upload / edit sheet. Pass [existing] to edit a record's
/// metadata, or [initialType] to pre-select a category for a new record
/// (e.g. whichever type filter chip is currently active on the records
/// library, so uploading while viewing "Military" defaults to Military
/// instead of always Birth).
Future<void> showRecordUploadSheet(
  BuildContext context,
  WidgetRef ref, {
  Record? existing,
  RecordType? initialType,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) =>
        _RecordUploadSheet(existing: existing, initialType: initialType),
  );
}

class _RecordUploadSheet extends ConsumerStatefulWidget {
  const _RecordUploadSheet({this.existing, this.initialType});
  final Record? existing;
  final RecordType? initialType;

  @override
  ConsumerState<_RecordUploadSheet> createState() => _RecordUploadSheetState();
}

class _RecordUploadSheetState extends ConsumerState<_RecordUploadSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _repository;
  late RecordType _type;
  DateTime? _date;
  late Set<String> _linkedIds;

  PlatformFile? _pickedFile;
  bool _runOcr = true;
  bool _saving = false;
  String? _statusMessage;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Record? e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _repository = TextEditingController(text: e?.repository ?? '');
    _type = e?.type ?? widget.initialType ?? RecordType.birth;
    _date = e?.date;
    _linkedIds = <String>{...?e?.personIds};
  }

  @override
  void dispose() {
    _title.dispose();
    _repository.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'pdf',
        'doc',
        'docx',
        'txt',
      ],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(1980),
      firstDate: DateTime(1700),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _statusMessage = null;
    });

    try {
      final String treeId = ref.read(activeTreeIdProvider);
      final String id =
          widget.existing?.id ?? 'rec_${DateTime.now().microsecondsSinceEpoch}';

      String? fileUrl = widget.existing?.fileUrl;
      String? fileName = widget.existing?.fileName;
      String? ocrText = widget.existing?.ocrText;

      // Upload a newly-picked attachment.
      if (_pickedFile != null) {
        final bytes = _pickedFile!.bytes;
        if (bytes == null) {
          throw const ServerFailure('Could not read the selected file.');
        }
        setState(() => _statusMessage = 'Uploading…');
        final stored = await ref
            .read(recordStorageServiceProvider)
            .uploadRecordFile(
              recordId: id,
              fileName: _pickedFile!.name,
              bytes: bytes,
            );
        fileUrl = stored.url;
        fileName = stored.fileName;

        // OCR the freshly-uploaded file (best effort).
        if (_runOcr) {
          setState(() => _statusMessage = 'Extracting text…');
          final ocr = await ref
              .read(ocrServiceProvider)
              .extractText(fileUrl: fileUrl);
          if (ocr.hasText) {
            ocrText = ocr.text;
          } else if (!ocr.available && mounted) {
            // Non-fatal: keep going without OCR text.
            _statusMessage = ocr.message;
          }
        }
      }

      final Record record =
          (widget.existing ??
                  Record(id: id, treeId: treeId, type: _type, title: ''))
              .copyWith(
                type: _type,
                title: _title.text.trim(),
                repository: _repository.text.trim(),
                date: _date,
                fileUrl: fileUrl,
                fileName: fileName,
                ocrText: ocrText,
                personIds: _linkedIds.toList(),
                createdAt: widget.existing?.createdAt ?? DateTime.now(),
              );

      await ref.read(recordRepositoryProvider).upsertRecord(record);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = e is Failure
              ? e.message
              : 'Could not save the record.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final List<Person> persons =
        ref.watch(personsProvider).value ?? const <Person>[];

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isEdit ? 'Edit record' : 'Upload record',
                style: text.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              _FilePickerTile(
                file: _pickedFile,
                existingName: widget.existing?.fileName,
                onPick: _saving ? null : _pickFile,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('TYPE', style: text.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<RecordType>(
                initialValue: _type,
                items: RecordType.values
                    .map(
                      (t) => DropdownMenuItem<RecordType>(
                        value: t,
                        child: Text(t.label),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (t) {
                        if (t != null) setState(() => _type = t);
                      },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _title,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Subject / title',
                  hintText: 'e.g. Adaeze Okonkwo',
                ),
                // A title is optional when a file is attached — the card falls
                // back to the record type (e.g. "Birth cert"). Require one only
                // when there's no attachment to identify the record by.
                validator: (v) {
                  final bool hasFile =
                      _pickedFile != null || widget.existing?.fileUrl != null;
                  if (hasFile) return null;
                  return (v ?? '').trim().isEmpty
                      ? 'Add a title or attach a file.'
                      : null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _repository,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Source / repository',
                  hintText: 'e.g. Lagos State Registry',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _DateField(
                date: _date,
                onTap: _saving ? null : _pickDate,
                onClear: _saving ? null : () => setState(() => _date = null),
              ),
              if (persons.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text('LINKED PEOPLE (OPTIONAL)', style: text.labelSmall),
                const SizedBox(height: 2),
                Text(
                  'Tap to link this record to people, or leave blank.',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final Person p in persons)
                      FilterChip(
                        label: Text(p.fullName),
                        selected: _linkedIds.contains(p.id),
                        onSelected: _saving
                            ? null
                            : (sel) => setState(() {
                                if (sel) {
                                  _linkedIds.add(p.id);
                                } else {
                                  _linkedIds.remove(p.id);
                                }
                              }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _runOcr,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _runOcr = v ?? true),
                title: const Text('Extract text (OCR) after upload'),
                subtitle: const Text(
                  'Runs on images, PDFs and .docx files when connected.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_statusMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _statusMessage!,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(_isEdit ? 'Save changes' : 'Save record'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePickerTile extends StatelessWidget {
  const _FilePickerTile({
    required this.file,
    required this.existingName,
    required this.onPick,
  });

  final PlatformFile? file;
  final String? existingName;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? name = file?.name ?? existingName;
    final bool hasFile = name != null;

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              hasFile ? Icons.insert_drive_file_outlined : Icons.upload_file,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hasFile ? name : 'Choose a file',
                    style: text.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('Image, PDF or document', style: text.bodySmall),
                ],
              ),
            ),
            Text(
              hasFile ? 'Change' : 'Browse',
              style: text.labelLarge?.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? date;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('DATE', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    date == null
                        ? 'Not set'
                        : '${date!.day.toString().padLeft(2, '0')}/'
                              '${date!.month.toString().padLeft(2, '0')}/'
                              '${date!.year}',
                    style: text.bodyLarge,
                  ),
                ),
                if (date != null && onClear != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

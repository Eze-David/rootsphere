import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/african_locations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../tree/data/services/geocoding_service.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../data/services/opportunity_subject_storage_service.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../providers/opportunity_providers.dart';

const List<String> _subjectFileExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'heic',
  'pdf',
  'doc',
  'docx',
];

/// Posts a new opportunity to the board. Beyond the task itself (title,
/// description, location, required role), the requester can optionally
/// describe *who* the research is about — name variants, country, photos,
/// and supporting documents — so a Finder/Indexer has something to work
/// from. That subject information is intentionally kept out of the public
/// board (see 20260722070000_opportunity_subjects.sql's RLS): it only ever
/// surfaces once someone has actually claimed the opportunity, in
/// [ClaimWorkspaceScreen].
Future<void> showAddOpportunitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => const _AddOpportunitySheet(),
  );
}

class _AddOpportunitySheet extends ConsumerStatefulWidget {
  const _AddOpportunitySheet();

  @override
  ConsumerState<_AddOpportunitySheet> createState() =>
      _AddOpportunitySheetState();
}

class _AddOpportunitySheetState extends ConsumerState<_AddOpportunitySheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nickNameController = TextEditingController();
  final TextEditingController _additionalInfoController =
      TextEditingController();

  CollaborationRole _selectedRole = CollaborationRole.finder;
  bool _sendToCompany = false;
  String _country = '';
  final List<PlatformFile> _photos = <PlatformFile>[];
  final List<PlatformFile> _documents = <PlatformFile>[];
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nickNameController.dispose();
    _additionalInfoController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null) return;
    setState(() => _photos.addAll(result.files));
  }

  Future<void> _pickDocuments() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null) return;
    final List<PlatformFile> allowed = result.files
        .where((f) => _isAllowedExtension(f.name))
        .toList();
    if (allowed.length < result.files.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some files were skipped — unsupported file type.'),
        ),
      );
    }
    if (allowed.isEmpty) return;
    setState(() => _documents.addAll(allowed));
  }

  bool _isAllowedExtension(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _subjectFileExtensions.contains(
      name.substring(dot + 1).toLowerCase(),
    );
  }

  Future<void> _submit() async {
    final String title = _titleController.text.trim();
    final String description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and description are required.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final String treeId = ref.read(activeTreeIdProvider);
      final String location = _locationController.text.trim();
      // Resolve the typed location to coordinates up front (same cached
      // `geocode` function as the map screens) so the opportunity has
      // explicit lat/lng from creation, rather than relying on the map to
      // geocode the text every time.
      final GeocodeResult? geo = location.isEmpty
          ? null
          : await ref.read(geocodingServiceProvider).geocode(location);

      final CollaborationOpportunity opportunity = await ref
          .read(opportunityControllerProvider.notifier)
          .createOpportunity(
            treeId: treeId,
            title: title,
            description: description,
            location: location.isEmpty ? null : location,
            latitude: geo?.lat,
            longitude: geo?.lon,
            requiredRole: _selectedRole,
            forCompany: _sendToCompany,
          );

      await _maybeSaveSubject(opportunity.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _sendToCompany ? 'Sent to the company.' : 'Opportunity added.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _maybeSaveSubject(String opportunityId) async {
    final OpportunitySubject draft = OpportunitySubject(
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      nickName: _nickNameController.text.trim(),
      country: _country,
      additionalInfo: _additionalInfoController.text.trim().isEmpty
          ? null
          : _additionalInfoController.text.trim(),
    );
    if (draft.isEmpty && _photos.isEmpty && _documents.isEmpty) return;

    final OpportunitySubjectStorageService storage =
        OpportunitySubjectStorageService();
    final List<String> photoUrls = <String>[];
    for (final PlatformFile file in _photos) {
      photoUrls.add(
        await storage.uploadFile(
          opportunityId: opportunityId,
          fileName: file.name,
          bytes: file.bytes!,
        ),
      );
    }
    final List<String> documentUrls = <String>[];
    for (final PlatformFile file in _documents) {
      documentUrls.add(
        await storage.uploadFile(
          opportunityId: opportunityId,
          fileName: file.name,
          bytes: file.bytes!,
        ),
      );
    }

    await ref
        .read(opportunityControllerProvider.notifier)
        .saveSubject(
          opportunityId,
          OpportunitySubject(
            firstName: draft.firstName,
            middleName: draft.middleName,
            lastName: draft.lastName,
            nickName: draft.nickName,
            country: draft.country,
            additionalInfo: draft.additionalInfo,
            photoUrls: photoUrls,
            documentUrls: documentUrls,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Add opportunity',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Required role', style: text.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<CollaborationRole>(
              segments: <ButtonSegment<CollaborationRole>>[
                ButtonSegment<CollaborationRole>(
                  value: CollaborationRole.finder,
                  label: const Text('Finder'),
                  icon: const Icon(Icons.search, size: 16),
                ),
                ButtonSegment<CollaborationRole>(
                  value: CollaborationRole.indexer,
                  label: const Text('Indexer'),
                  icon: const Icon(Icons.keyboard, size: 16),
                ),
              ],
              selected: <CollaborationRole>{_selectedRole},
              onSelectionChanged: (selected) =>
                  setState(() => _selectedRole = selected.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _selectedRole.description,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            CheckboxListTile(
              value: _sendToCompany,
              onChanged: (checked) =>
                  setState(() => _sendToCompany = checked ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Send directly to the company'),
              subtitle: const Text(
                "Skip the public board — only Rootsphere's own team will see "
                'and handle this request.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            Text('SUBJECT DETAILS (OPTIONAL)', style: text.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Who is this research about? Only visible to whoever claims "
              "this opportunity — never shown on the public board.",
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _firstNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _middleNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Middle name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _lastNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _nickNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nickname'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              value: _country.isEmpty ? null : _country,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Country'),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('— Select country —'),
                ),
                ...africanCountries.map(
                  (c) => DropdownMenuItem<String>(value: c, child: Text(c)),
                ),
              ],
              onChanged: (v) => setState(() => _country = v ?? ''),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _additionalInfoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Any other information (optional)',
                hintText: 'Aliases, approximate dates, known relatives...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('PHOTOS', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final PlatformFile file in _photos)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PickedFileTile(
                  file: file,
                  onRemove: _submitting
                      ? null
                      : () => setState(() => _photos.remove(file)),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickPhotos,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(_photos.isEmpty ? 'Add a photo' : 'Add another'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('DOCUMENTS', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final PlatformFile file in _documents)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PickedFileTile(
                  file: file,
                  onRemove: _submitting
                      ? null
                      : () => setState(() => _documents.remove(file)),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickDocuments,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(
                _documents.isEmpty ? 'Add a document' : 'Add another',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedFileTile extends StatelessWidget {
  const _PickedFileTile({required this.file, required this.onRemove});

  final PlatformFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.insert_drive_file_outlined,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

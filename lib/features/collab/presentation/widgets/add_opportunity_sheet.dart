import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/african_locations.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../tree/data/services/geocoding_service.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../data/services/opportunity_subject_storage_service.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../../domain/entities/research_request.dart';
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
  // Public board fields.
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  // A. Requester's information.
  final TextEditingController _requesterNameController =
      TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final Set<String> _contactMethods = <String>{};

  // B. Person or family to be researched.
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nickNameController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _birthPlaceController = TextEditingController();
  final TextEditingController _marriageController = TextEditingController();
  final TextEditingController _deathController = TextEditingController();
  final TextEditingController _spousesController = TextEditingController();
  final TextEditingController _parentsController = TextEditingController();
  final TextEditingController _relativesController = TextEditingController();
  final TextEditingController _ethnicGroupController = TextEditingController();
  final TextEditingController _religionController = TextEditingController();
  String _country = '';

  // C. Research request.
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _additionalInfoController =
      TextEditingController();
  final Set<String> _sourcesChecked = <String>{};
  final TextEditingController _sourcesOtherController = TextEditingController();

  // D. Documents provided.
  final TextEditingController _documentsListController =
      TextEditingController();
  final List<PlatformFile> _photos = <PlatformFile>[];
  final List<PlatformFile> _documents = <PlatformFile>[];

  // E. Desired research output.
  final Set<String> _desiredOutputs = <String>{};
  final TextEditingController _outputsOtherController = TextEditingController();

  // F. Declaration and consent.
  bool _declarationAccepted = false;

  CollaborationRole _selectedRole = CollaborationRole.finder;
  bool _sendToCompany = false;
  bool _submitting = false;

  List<TextEditingController> get _controllers => <TextEditingController>[
    _titleController,
    _descriptionController,
    _locationController,
    _requesterNameController,
    _addressController,
    _phoneController,
    _emailController,
    _relationshipController,
    _firstNameController,
    _middleNameController,
    _lastNameController,
    _nickNameController,
    _birthDateController,
    _birthPlaceController,
    _marriageController,
    _deathController,
    _spousesController,
    _parentsController,
    _relativesController,
    _ethnicGroupController,
    _religionController,
    _questionController,
    _additionalInfoController,
    _sourcesOtherController,
    _documentsListController,
    _outputsOtherController,
  ];

  @override
  void initState() {
    super.initState();
    // Prefill section A from the signed-in account; the requester can edit.
    final AppUser? user = ref.read(authStateProvider).value;
    if (user != null) {
      _requesterNameController.text = user.displayName ?? '';
      _emailController.text = user.email;
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
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

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final String title = _titleController.text.trim();
    final String description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      _showError('Title and summary are required.');
      return;
    }
    if (_requesterNameController.text.trim().isEmpty) {
      _showError("Please enter your full name (section A).");
      return;
    }
    if (_questionController.text.trim().isEmpty) {
      _showError('Please state your main research question (section C).');
      return;
    }
    if (!_declarationAccepted) {
      _showError('Please accept the declaration and consent (section F).');
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

      await _saveSubject(opportunity.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_sendToCompany ? 'Sent to the company' : 'Request posted'}'
              ' · Ref ${researchReferenceNumber(opportunity.id)}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError('Could not add: ${friendlyErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveSubject(String opportunityId) async {
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

    String t(TextEditingController c) => c.text.trim();
    final String additionalInfo = t(_additionalInfoController);

    await ref
        .read(opportunityControllerProvider.notifier)
        .saveSubject(
          opportunityId,
          OpportunitySubject(
            firstName: t(_firstNameController),
            middleName: t(_middleNameController),
            lastName: t(_lastNameController),
            nickName: t(_nickNameController),
            country: _country,
            additionalInfo: additionalInfo.isEmpty ? null : additionalInfo,
            photoUrls: photoUrls,
            documentUrls: documentUrls,
            request: ResearchRequest(
              requesterName: t(_requesterNameController),
              requesterAddress: t(_addressController),
              requesterPhone: t(_phoneController),
              requesterEmail: t(_emailController),
              contactMethods: _contactMethods.toList(),
              relationship: t(_relationshipController),
              birthDate: t(_birthDateController),
              birthPlace: t(_birthPlaceController),
              marriage: t(_marriageController),
              death: t(_deathController),
              spouses: t(_spousesController),
              parents: t(_parentsController),
              relatives: t(_relativesController),
              ethnicGroup: t(_ethnicGroupController),
              religion: t(_religionController),
              researchQuestion: t(_questionController),
              sourcesChecked: _sourcesChecked.toList(),
              sourcesOther: t(_sourcesOtherController),
              documentsProvided: t(_documentsListController),
              desiredOutputs: _desiredOutputs.toList(),
              outputsOther: t(_outputsOtherController),
              declarationAccepted: _declarationAccepted,
              declaredAt: DateTime.now(),
            ),
          ),
        );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.words,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(child: a),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: b),
    ],
  );

  Widget _chips(List<String> options, Set<String> selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          for (final String option in options)
            FilterChip(
              label: Text(option),
              selected: selected.contains(option),
              onSelected: (on) => setState(
                () => on ? selected.add(option) : selected.remove(option),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;
    const TextCapitalization sentences = TextCapitalization.sentences;

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
              'ROOTSPHERE FAMILY HISTORY FOUNDATION',
              style: text.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Research Request',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Family History & Genealogy Research Request Form',
              style: text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Public board listing ──────────────────────────────────────
            const _SectionHeader(
              title: 'Opportunity listing',
              subtitle:
                  'Shown on the collaboration board. Keep personal details '
                  'out of these fields.',
            ),
            _field(_titleController, 'Title', capitalization: sentences),
            _field(
              _descriptionController,
              'Short public summary',
              maxLines: 3,
              capitalization: sentences,
            ),
            _field(_locationController, 'Location (optional)'),
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
              style: text.bodySmall?.copyWith(color: muted),
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
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.lock_outline, size: 18, color: muted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Sections A–F are private: only the researcher who '
                      'claims this request and RootSphere admins can see them.',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),

            // ── A ─────────────────────────────────────────────────────────
            const _SectionHeader(letter: 'A', title: "Requester's information"),
            _field(_requesterNameController, 'Full name *'),
            _field(_addressController, 'Address', maxLines: 2),
            _pair(
              _field(
                _phoneController,
                'Phone number',
                keyboardType: TextInputType.phone,
              ),
              _field(
                _emailController,
                'Email address',
                keyboardType: TextInputType.emailAddress,
                capitalization: TextCapitalization.none,
              ),
            ),
            Text('Preferred method of contact', style: text.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            _chips(ResearchRequest.contactMethodOptions, _contactMethods),
            _field(
              _relationshipController,
              'Relationship to the person/family being researched',
              capitalization: sentences,
            ),

            // ── B ─────────────────────────────────────────────────────────
            const _SectionHeader(
              letter: 'B',
              title: 'Person or family to be researched',
            ),
            _pair(
              _field(_firstNameController, 'First name'),
              _field(_middleNameController, 'Middle name'),
            ),
            _pair(
              _field(_lastNameController, 'Last name'),
              _field(_nickNameController, 'Other names/spellings'),
            ),
            _pair(
              _field(_birthDateController, 'Approx. date of birth'),
              _field(_birthPlaceController, 'Place of birth/origin'),
            ),
            _field(_marriageController, 'Date/place of marriage'),
            _field(_deathController, 'Date/place of death'),
            _field(_spousesController, 'Spouse(s)'),
            _field(_parentsController, 'Parents (if known)'),
            _field(
              _relativesController,
              'Children/siblings/other relatives known',
              maxLines: 3,
            ),
            _pair(
              _field(_ethnicGroupController, 'Ethnic group/community'),
              _field(_religionController, 'Religion/church'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: DropdownButtonFormField<String>(
                initialValue: _country.isEmpty ? null : _country,
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
            ),

            // ── C ─────────────────────────────────────────────────────────
            const _SectionHeader(letter: 'C', title: 'Research request'),
            _field(
              _questionController,
              'Main research question *',
              hint: 'Clearly state what you want the researcher to establish.',
              maxLines: 3,
              capitalization: sentences,
            ),
            _field(
              _additionalInfoController,
              'Information already known',
              maxLines: 3,
              capitalization: sentences,
            ),
            Text('Sources already checked', style: text.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            _chips(ResearchRequest.sourceOptions, _sourcesChecked),
            _field(_sourcesOtherController, 'Other sources checked'),

            // ── D ─────────────────────────────────────────────────────────
            const _SectionHeader(
              letter: 'D',
              title: 'Documents provided',
              subtitle:
                  'Photographs, certificates, family trees, interview notes '
                  'or other materials. Clear digital copies are preferred '
                  'over originals.',
            ),
            _field(
              _documentsListController,
              'List of documents supplied',
              hint: 'One per line',
              maxLines: 3,
              capitalization: sentences,
            ),
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
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickPhotos,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Add photo'),
                ),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickDocuments,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Add document'),
                ),
              ],
            ),

            // ── E ─────────────────────────────────────────────────────────
            const _SectionHeader(letter: 'E', title: 'Desired research output'),
            _chips(ResearchRequest.outputOptions, _desiredOutputs),
            _field(_outputsOtherController, 'Other output'),

            // ── F ─────────────────────────────────────────────────────────
            const _SectionHeader(
              letter: 'F',
              title: "Requester's declaration and consent",
            ),
            Text(
              ResearchRequest.declarationText,
              style: text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: _declarationAccepted,
              onChanged: (checked) =>
                  setState(() => _declarationAccepted = checked ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I agree to the declaration and consent *'),
              subtitle: ListenableBuilder(
                listenable: _requesterNameController,
                builder: (_, _) {
                  final String name = _requesterNameController.text.trim();
                  final DateTime now = DateTime.now();
                  final String date =
                      '${now.day.toString().padLeft(2, '0')}/'
                      '${now.month.toString().padLeft(2, '0')}/${now.year}';
                  return Text(
                    name.isEmpty ? 'Date: $date' : 'Signed: $name · $date',
                  );
                },
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
                    : const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({this.letter, required this.title, this.subtitle});

  final String? letter;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              if (letter != null) ...<Widget>[
                CircleAvatar(
                  radius: 13,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    letter!,
                    style: text.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: text.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
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

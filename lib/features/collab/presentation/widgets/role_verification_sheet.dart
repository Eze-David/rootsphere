import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/services/role_verification_storage_service.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/role_verification_providers.dart';

const List<String> _idAndCertExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'heic',
  'pdf',
  'doc',
  'docx',
];

/// Lets the signed-in user apply (or reapply) to be verified for [role],
/// required before they can claim an opportunity needing it. Reviewed by
/// the company — see supabase/migrations/20260722020000_role_verifications.sql.
Future<void> showRoleVerificationSheet(
  BuildContext context,
  CollaborationRole role,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _RoleVerificationSheet(role: role),
  );
}

class _RoleVerificationSheet extends ConsumerStatefulWidget {
  const _RoleVerificationSheet({required this.role});
  final CollaborationRole role;

  @override
  ConsumerState<_RoleVerificationSheet> createState() =>
      _RoleVerificationSheetState();
}

class _RoleVerificationSheetState
    extends ConsumerState<_RoleVerificationSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final List<PlatformFile> _certificates = <PlatformFile>[];
  PlatformFile? _governmentId;
  // Purely a storage-folder key, not the eventual DB row id (that's
  // server-generated) — just needs to be unique per application attempt.
  late final String _applicationKey =
      '${widget.role.name}_${DateTime.now().microsecondsSinceEpoch}';
  bool _submitting = false;
  bool _prefilledEmail = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // FileType.custom + allowedExtensions restricts iOS's document browser to
  // Files-app locations only (Photos isn't offered as a source). FileType.any
  // keeps Photos available; extensions are validated after picking instead.
  bool _isAllowedExtension(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _idAndCertExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  Future<void> _pickCertificates() async {
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
    setState(() => _certificates.addAll(allowed));
  }

  Future<void> _pickGovernmentId() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final PlatformFile file = result.files.first;
    if (!_isAllowedExtension(file.name)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unsupported file type.')));
      }
      return;
    }
    setState(() => _governmentId = file);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_governmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A government-issued ID is required to apply.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final RoleVerificationStorageService storage =
          RoleVerificationStorageService();
      final List<String> documentUrls = <String>[];
      for (final PlatformFile file in _certificates) {
        final url = await storage.uploadDocument(
          applicationId: _applicationKey,
          fileName: file.name,
          bytes: file.bytes!,
        );
        documentUrls.add(url);
      }
      final String governmentIdUrl = await storage.uploadDocument(
        applicationId: _applicationKey,
        fileName: _governmentId!.name,
        bytes: _governmentId!.bytes!,
      );

      final String note = _noteController.text.trim();
      await ref
          .read(roleVerificationRepositoryProvider)
          .apply(
            role: widget.role,
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            governmentIdUrl: governmentIdUrl,
            note: note.isEmpty ? null : note,
            documentUrls: documentUrls,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Application submitted — the company will review it.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // Pre-fill the contact email with the account's once (not on every
    // rebuild, so an edit the user makes isn't clobbered).
    if (!_prefilledEmail) {
      final AppUser? user = ref.read(authStateProvider).value;
      if (user != null && user.email.isNotEmpty) {
        _emailController.text = user.email;
      }
      _prefilledEmail = true;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Apply to become a ${widget.role.label}',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(widget.role.description, style: text.bodyMedium),
              const SizedBox(height: AppSpacing.lg),
              Text(
                "Not every opportunity needs specialist skill, but this one "
                "does — the company reviews applications so requesters can "
                "trust whoever claims their work is actually qualified for "
                "it, and can reach them if needed.",
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (v) {
                  final String value = (v ?? '').trim();
                  if (value.isEmpty) return 'Email is required.';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                    return 'Enter a valid email.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Phone number is required.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _noteController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Relevant experience (optional)',
                  hintText: 'e.g. 3 years indexing parish records for...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('GOVERNMENT-ISSUED ID', style: text.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Used only to confirm identity before approval — not shown '
                'publicly.',
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_governmentId != null)
                _PickedFileTile(
                  file: _governmentId!,
                  onRemove: _submitting
                      ? null
                      : () => setState(() => _governmentId = null),
                )
              else
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickGovernmentId,
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Upload ID'),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text('CERTIFICATES (OPTIONAL)', style: text.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              for (final PlatformFile file in _certificates)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _PickedFileTile(
                    file: file,
                    onRemove: _submitting
                        ? null
                        : () => setState(() => _certificates.remove(file)),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickCertificates,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(
                  _certificates.isEmpty ? 'Add a certificate' : 'Add another',
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
                      : const Text('Submit application'),
                ),
              ),
            ],
          ),
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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Lets the signed-in user edit their avatar, display name, and a short
/// "About me" bio — the fields shown alongside the avatar/name/email on
/// Profile.
Future<void> showEditProfileSheet(
  BuildContext context,
  WidgetRef ref,
  AppUser user,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _EditProfileSheet(user: user),
  );
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});
  final AppUser user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  final ImagePicker _picker = ImagePicker();

  XFile? _pickedAvatar;
  Uint8List? _pickedAvatarBytes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.displayName ?? '');
    _bio = TextEditingController(text: widget.user.bio ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      maxHeight: 1000,
      imageQuality: 85,
    );
    if (file == null) return;
    // Read into memory for a cross-platform preview (dart:io's File/
    // FileImage don't work on web — MemoryImage does everywhere).
    final Uint8List bytes = await file.readAsBytes();
    if (mounted) {
      setState(() {
        _pickedAvatar = file;
        _pickedAvatarBytes = bytes;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? avatarUrl;
      if (_pickedAvatar != null) {
        avatarUrl = await ref
            .read(avatarStorageServiceProvider)
            .uploadAvatar(file: _pickedAvatar!);
      }
      final bool ok = await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            displayName: _name.text.trim(),
            avatarUrl: avatarUrl,
            bio: _bio.text.trim(),
          );
      if (ok && mounted) Navigator.of(context).pop();
      if (!ok && mounted) {
        setState(() => _error = 'Could not save your profile. Please try again.');
      }
    } catch (e) {
      setState(() => _error = e is Failure ? e.message : 'Could not save your profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final ImageProvider? avatarImage = _pickedAvatarBytes != null
        ? MemoryImage(_pickedAvatarBytes!)
        : (widget.user.avatarUrl != null
              ? NetworkImage(widget.user.avatarUrl!)
              : null);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Edit profile', style: text.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: InkWell(
                onTap: _saving ? null : _pickAvatar,
                borderRadius: BorderRadius.circular(48),
                child: Stack(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.cream,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(Icons.person, size: 40, color: AppColors.primary)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _bio,
              enabled: !_saving,
              maxLines: 4,
              maxLength: 280,
              decoration: const InputDecoration(
                labelText: 'About me',
                hintText: 'A short bio for your profile',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
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
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

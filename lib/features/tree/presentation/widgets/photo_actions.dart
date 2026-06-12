import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/person.dart';
import '../providers/tree_providers.dart';

/// Shared photo flows for a [Person]: pick → upload → persist, plus removal.
///
/// Uploads go through [PhotoStorageService] (Supabase Storage when configured,
/// local copy otherwise) and the resulting reference is saved on the person via
/// the tree repository.
class PhotoActions {
  PhotoActions._();

  static final ImagePicker _picker = ImagePicker();

  /// Picks an image, uploads it, and sets it as the person's profile photo.
  static Future<void> setProfilePhoto(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    final ImageSource? source = await _chooseSource(context);
    if (source == null || !context.mounted) return;
    await _pickUpload(
      context,
      ref,
      person,
      source,
      onUploaded: (reference) => person.copyWith(photoUrl: reference),
    );
  }

  /// Picks an image, uploads it, and appends it to the photo gallery.
  static Future<void> addGalleryPhoto(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    final ImageSource? source = await _chooseSource(context);
    if (source == null || !context.mounted) return;
    await _pickUpload(
      context,
      ref,
      person,
      source,
      onUploaded: (reference) => person.copyWith(
        photoGallery: <String>[...person.photoGallery, reference],
      ),
    );
  }

  /// Removes a gallery photo (and deletes the stored object/file).
  static Future<void> removeGalleryPhoto(
    BuildContext context,
    WidgetRef ref,
    Person person,
    String reference,
  ) async {
    final storage = ref.read(photoStorageServiceProvider);
    final repo = ref.read(treeRepositoryProvider);
    await repo.upsertPerson(
      person.copyWith(
        photoGallery:
            person.photoGallery.where((r) => r != reference).toList(),
        // Clear the avatar too if it pointed at this image.
        photoUrl: person.photoUrl == reference ? null : person.photoUrl,
      ),
    );
    await storage.deletePersonPhoto(reference);
  }

  /// Removes the profile photo.
  static Future<void> removeProfilePhoto(
    WidgetRef ref,
    Person person,
  ) async {
    final repo = ref.read(treeRepositoryProvider);
    final String? ref0 = person.photoUrl;
    await repo.upsertPerson(person.copyWith(photoUrl: null));
    // Only delete the underlying object if it isn't also in the gallery.
    if (ref0 != null && !person.photoGallery.contains(ref0)) {
      await ref.read(photoStorageServiceProvider).deletePersonPhoto(ref0);
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  static Future<void> _pickUpload(
    BuildContext context,
    WidgetRef ref,
    Person person,
    ImageSource source, {
    required Person Function(String reference) onUploaded,
  }) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (file == null) return;
    if (!context.mounted) return;

    _showProgress(context);
    try {
      final storage = ref.read(photoStorageServiceProvider);
      final repo = ref.read(treeRepositoryProvider);
      final String reference = await storage.uploadPersonPhoto(
        personId: person.id,
        file: file,
      );
      await repo.upsertPerson(onUploaded(reference));
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final String msg =
            e is Failure ? e.message : 'Could not upload photo.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  static Future<ImageSource?> _chooseSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  static void _showProgress(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }
}

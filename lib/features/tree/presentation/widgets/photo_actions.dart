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

  /// Picks (or records) a video, uploads it, and appends it to the video
  /// gallery.
  static Future<void> addGalleryVideo(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    final ImageSource? source = await _chooseSource(context, video: true);
    if (source == null || !context.mounted) return;

    final XFile? file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 10),
    );
    if (file == null || !context.mounted) return;

    _showProgress(context);
    try {
      final storage = ref.read(photoStorageServiceProvider);
      final repo = ref.read(treeRepositoryProvider);
      final String reference = await storage.uploadPersonPhoto(
        personId: person.id,
        file: file,
      );
      await repo.upsertPerson(person.copyWith(
        videoGallery: <String>[...person.videoGallery, reference],
      ));
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (context.mounted) _handleError(context, e, 'Could not upload video.');
    }
  }

  /// Uploads a recorded voice note (at [path]) and appends it to the voice
  /// notes list.
  static Future<void> saveVoiceNote(
    BuildContext context,
    WidgetRef ref,
    Person person,
    String path,
  ) async {
    _showProgress(context);
    try {
      final storage = ref.read(photoStorageServiceProvider);
      final repo = ref.read(treeRepositoryProvider);
      final String reference = await storage.uploadPersonFile(
        personId: person.id,
        path: path,
      );
      await repo.upsertPerson(person.copyWith(
        voiceNotes: <String>[...person.voiceNotes, reference],
      ));
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (context.mounted) {
        _handleError(context, e, 'Could not save voice note.');
      }
    }
  }

  /// Removes a video from the gallery (and deletes the stored object/file).
  static Future<void> removeVideo(
    WidgetRef ref,
    Person person,
    String reference,
  ) async {
    final storage = ref.read(photoStorageServiceProvider);
    final repo = ref.read(treeRepositoryProvider);
    await repo.upsertPerson(person.copyWith(
      videoGallery: person.videoGallery.where((r) => r != reference).toList(),
    ));
    await storage.deletePersonPhoto(reference);
  }

  /// Removes a voice note (and deletes the stored object/file).
  static Future<void> removeVoiceNote(
    WidgetRef ref,
    Person person,
    String reference,
  ) async {
    final storage = ref.read(photoStorageServiceProvider);
    final repo = ref.read(treeRepositoryProvider);
    await repo.upsertPerson(person.copyWith(
      voiceNotes: person.voiceNotes.where((r) => r != reference).toList(),
    ));
    await storage.deletePersonPhoto(reference);
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
      if (context.mounted) _handleError(context, e, 'Could not upload photo.');
    }
  }

  static void _handleError(BuildContext context, Object e, String fallback) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    final String msg = e is Failure ? e.message : fallback;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  static Future<ImageSource?> _chooseSource(
    BuildContext context, {
    bool video = false,
  }) {
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
              leading: Icon(
                video
                    ? Icons.videocam_outlined
                    : Icons.photo_camera_outlined,
              ),
              title: Text(video ? 'Record video' : 'Take photo'),
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

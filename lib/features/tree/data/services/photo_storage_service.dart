import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';

/// Uploads person photos to Supabase Storage when configured, falling back to
/// a persisted local copy on mobile/desktop when it isn't (so the feature works
/// offline / in demos).
///
/// Uploads are byte-based ([XFile.readAsBytes]) so the same code path works on
/// web, mobile and desktop. Returned strings are references suitable for
/// [AdaptiveImage]:
///  * `https://…` public URLs (Supabase), or
///  * absolute file paths (local fallback, non-web only).
class PhotoStorageService {
  PhotoStorageService();

  static const String bucket = 'photos';

  /// Reads [file], uploads it for [personId], and returns a reference
  /// (public URL or local path). Works for any media kind (image, video).
  Future<String> uploadPersonPhoto({
    required String personId,
    required XFile file,
  }) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const ServerFailure('Selected file could not be read.');
    }
    final String ext = _extension(file.name.isNotEmpty ? file.name : file.path);
    return _store(personId: personId, bytes: bytes, ext: ext);
  }

  /// Uploads a file at [path] (e.g. a recorded voice note) for [personId].
  Future<String> uploadPersonFile({
    required String personId,
    required String path,
  }) async {
    if (kIsWeb) {
      throw const ServerFailure('Recording is not supported on the web.');
    }
    final Uint8List bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) {
      throw const ServerFailure('Recording could not be read.');
    }
    return _store(personId: personId, bytes: bytes, ext: _extension(path));
  }

  Future<String> _store({
    required String personId,
    required Uint8List bytes,
    required String ext,
  }) async {
    if (SupabaseConfig.isReady) {
      return _uploadToSupabase(personId: personId, bytes: bytes, ext: ext);
    }
    if (kIsWeb) {
      // No local filesystem on web — Supabase is required there.
      throw const ServerFailure(
        'Connect Supabase to upload media on the web.',
      );
    }
    return _persistLocally(personId: personId, bytes: bytes, ext: ext);
  }

  /// Removes a previously uploaded photo. Local files are deleted; Supabase
  /// objects are removed from the bucket. Best-effort — failures are ignored
  /// so a broken reference never blocks the UI.
  Future<void> deletePersonPhoto(String reference) async {
    try {
      if (reference.startsWith('http')) {
        if (!SupabaseConfig.isReady) return;
        final String path = _objectPathFromPublicUrl(reference);
        if (path.isNotEmpty) {
          await SupabaseConfig.client.storage.from(bucket).remove(<String>[path]);
        }
      } else if (!kIsWeb) {
        final File f = File(reference);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  // ── Supabase ────────────────────────────────────────────────────────────────

  Future<String> _uploadToSupabase({
    required String personId,
    required Uint8List bytes,
    required String ext,
  }) async {
    try {
      final client = SupabaseConfig.client;
      final String userId = client.auth.currentUser?.id ?? 'anon';
      final String objectPath =
          '$userId/$personId/${DateTime.now().microsecondsSinceEpoch}.$ext';

      await client.storage.from(bucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentType(ext),
              upsert: true,
            ),
          );
      return client.storage.from(bucket).getPublicUrl(objectPath);
    } on StorageException catch (e) {
      throw ServerFailure('Upload failed: ${e.message}');
    } catch (_) {
      throw const ServerFailure('Upload failed. Please try again.');
    }
  }

  // ── Local fallback (non-web) ────────────────────────────────────────────────

  Future<String> _persistLocally({
    required String personId,
    required Uint8List bytes,
    required String ext,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/person_photos/$personId');
    if (!await dir.exists()) await dir.create(recursive: true);
    final String dest =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final File created = await File(dest).writeAsBytes(bytes);
    return created.path;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _extension(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    return path.substring(dot + 1).toLowerCase();
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      // Video.
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      // Audio.
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'caf':
        return 'audio/x-caf';
      default:
        return 'application/octet-stream';
    }
  }

  /// Extracts the object path from a Supabase public URL of the form
  /// `…/storage/v1/object/public/<bucket>/<path>`.
  String _objectPathFromPublicUrl(String url) {
    final String marker = '/public/$bucket/';
    final int i = url.indexOf(marker);
    if (i < 0) return '';
    return Uri.decodeComponent(url.substring(i + marker.length));
  }
}

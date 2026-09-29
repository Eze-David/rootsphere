import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';

/// Uploads the signed-in user's profile avatar to the Supabase Storage
/// `avatars` bucket, falling back to a persisted local copy on mobile/
/// desktop when Supabase isn't configured. Mirrors [PhotoStorageService] —
/// same upload/fallback shape — but one avatar per user (path
/// `<uid>/avatar.<ext>`, always overwritten) rather than per-person media.
class AvatarStorageService {
  AvatarStorageService();

  static const String bucket = 'avatars';

  Future<String> uploadAvatar({required XFile file}) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const ServerFailure('Selected image could not be read.');
    }
    final String ext = _extension(file.name.isNotEmpty ? file.name : file.path);

    if (SupabaseConfig.isReady) {
      return _uploadToSupabase(bytes: bytes, ext: ext);
    }
    if (kIsWeb) {
      throw const ServerFailure(
        'Connect Supabase to upload a photo on the web.',
      );
    }
    return _persistLocally(bytes: bytes, ext: ext);
  }

  Future<String> _uploadToSupabase({
    required Uint8List bytes,
    required String ext,
  }) async {
    try {
      final client = SupabaseConfig.client;
      final String userId = client.auth.currentUser?.id ?? 'anon';
      final String objectPath = '$userId/avatar.$ext';

      await client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: _contentType(ext), upsert: true),
          );
      // Cache-bust — the path never changes, so without a query param the
      // old image would keep showing from cache after a re-upload.
      final String base = client.storage.from(bucket).getPublicUrl(objectPath);
      return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
    } on StorageException catch (e) {
      throw ServerFailure('Upload failed: ${e.message}');
    } catch (_) {
      throw const ServerFailure('Upload failed. Please try again.');
    }
  }

  Future<String> _persistLocally({
    required Uint8List bytes,
    required String ext,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/avatar');
    if (!await dir.exists()) await dir.create(recursive: true);
    final String dest = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final File created = await File(dest).writeAsBytes(bytes);
    return created.path;
  }

  String _extension(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    return path.substring(dot + 1).toLowerCase();
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }
}

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';

/// Uploads "What to watch" media (photos, videos, and video cover images) to
/// the Supabase Storage `watch-media` bucket. Admin-only per the bucket's RLS
/// (`20260806000000_watch_items.sql`) — this doesn't have a local fallback
/// since only Supabase can actually enforce that restriction.
class WatchStorageService {
  WatchStorageService();

  static const String bucket = 'watch-media';

  /// Reads [file], uploads it under [itemId], and returns its public URL.
  Future<String> uploadMedia({
    required String itemId,
    required XFile file,
  }) async {
    if (!SupabaseConfig.isReady) {
      throw const ServerFailure('Connect Supabase to upload media.');
    }
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const ServerFailure('Selected file could not be read.');
    }
    final String ext = _extension(file.name.isNotEmpty ? file.name : file.path);
    try {
      final client = SupabaseConfig.client;
      final String userId = client.auth.currentUser?.id ?? 'anon';
      final String objectPath =
          '$userId/$itemId/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await client.storage
          .from(bucket)
          .uploadBinary(
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

  /// Best-effort removal of a previously uploaded object.
  Future<void> deleteMedia(String url) async {
    try {
      if (!SupabaseConfig.isReady || !url.startsWith('http')) return;
      final String path = _objectPathFromPublicUrl(url);
      if (path.isNotEmpty) {
        await SupabaseConfig.client.storage.from(bucket).remove(<String>[
          path,
        ]);
      }
    } catch (_) {
      // Best-effort cleanup.
    }
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
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'application/octet-stream';
    }
  }

  String _objectPathFromPublicUrl(String url) {
    final String marker = '/public/$bucket/';
    final int i = url.indexOf(marker);
    if (i < 0) return '';
    return Uri.decodeComponent(url.substring(i + marker.length));
  }
}

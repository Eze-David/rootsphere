import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';

/// The outcome of storing an archive attachment.
class StoredArchiveFile {
  const StoredArchiveFile({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

/// Uploads Digital Records Repository attachments (scans, photos, audio,
/// video) to the private Supabase Storage `archive_records` bucket, falling
/// back to a persisted local copy on mobile/desktop when Supabase isn't
/// configured. Mirrors [RecordStorageService] / [PhotoStorageService] so
/// behaviour and object-path conventions stay consistent
/// (`<uid>/<recordId>/<timestamp>.<ext>`).
class ArchiveStorageService {
  ArchiveStorageService();

  static const String bucket = 'archive_records';

  Future<StoredArchiveFile> uploadArchiveFile({
    required String recordId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const ServerFailure('Selected file could not be read.');
    }
    final String ext = _extension(fileName);

    if (SupabaseConfig.isReady) {
      return _uploadToSupabase(
        recordId: recordId,
        fileName: fileName,
        bytes: bytes,
        ext: ext,
      );
    }
    if (kIsWeb) {
      throw const ServerFailure(
        'Connect Supabase to upload records on the web.',
      );
    }
    return _persistLocally(
      recordId: recordId,
      fileName: fileName,
      bytes: bytes,
      ext: ext,
    );
  }

  /// Best-effort removal of a previously uploaded attachment.
  Future<void> deleteArchiveFile(String reference) async {
    try {
      if (reference.startsWith('http')) {
        if (!SupabaseConfig.isReady) return;
        final String path = _objectPathFromPublicUrl(reference);
        if (path.isNotEmpty) {
          await SupabaseConfig.client.storage.from(bucket).remove(<String>[
            path,
          ]);
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

  Future<StoredArchiveFile> _uploadToSupabase({
    required String recordId,
    required String fileName,
    required Uint8List bytes,
    required String ext,
  }) async {
    try {
      final client = SupabaseConfig.client;
      final String userId = client.auth.currentUser?.id ?? 'anon';
      final String objectPath =
          '$userId/$recordId/${DateTime.now().microsecondsSinceEpoch}.$ext';

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
      // The bucket is private (admin-only) — a signed URL, not a public one,
      // so playback/download works within the admin session.
      final String url = await client.storage
          .from(bucket)
          .createSignedUrl(objectPath, 60 * 60 * 24 * 7);
      return StoredArchiveFile(url: url, fileName: fileName);
    } on StorageException catch (e) {
      throw ServerFailure('Upload failed: ${e.message}');
    } catch (_) {
      throw const ServerFailure('Upload failed. Please try again.');
    }
  }

  // ── Local fallback (non-web) ────────────────────────────────────────────────

  Future<StoredArchiveFile> _persistLocally({
    required String recordId,
    required String fileName,
    required Uint8List bytes,
    required String ext,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/archive_records/$recordId');
    if (!await dir.exists()) await dir.create(recursive: true);
    final String dest =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final File created = await File(dest).writeAsBytes(bytes);
    return StoredArchiveFile(url: created.path, fileName: fileName);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _extension(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'bin';
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
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  /// Extracts the object path from a Supabase signed/public URL that
  /// contains `/object/<sign|public>/<bucket>/<path>`.
  String _objectPathFromPublicUrl(String url) {
    for (final String marker in <String>['/sign/$bucket/', '/public/$bucket/']) {
      final int i = url.indexOf(marker);
      if (i >= 0) {
        final String rest = url.substring(i + marker.length);
        final int q = rest.indexOf('?');
        return Uri.decodeComponent(q >= 0 ? rest.substring(0, q) : rest);
      }
    }
    return '';
  }
}

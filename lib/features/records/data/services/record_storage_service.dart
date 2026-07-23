import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';

/// The outcome of storing a record attachment.
class StoredFile {
  const StoredFile({required this.url, required this.fileName});

  /// An [AdaptiveImage]-compatible reference (public URL or local path).
  final String url;
  final String fileName;
}

/// Uploads record attachments (images, PDFs, documents) to the Supabase
/// Storage `records` bucket, falling back to a persisted local copy on
/// mobile/desktop when Supabase isn't configured.
///
/// Mirrors [PhotoStorageService] so behaviour and object-path conventions are
/// consistent (`<uid>/<recordId>/<timestamp>.<ext>`).
class RecordStorageService {
  RecordStorageService();

  static const String bucket = 'records';

  /// Uploads [bytes] (read from the picked file) for [recordId] and returns a
  /// reference plus the stored file name.
  Future<StoredFile> uploadRecordFile({
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
  Future<void> deleteRecordFile(String reference) async {
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

  Future<StoredFile> _uploadToSupabase({
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
      final String url = client.storage.from(bucket).getPublicUrl(objectPath);
      return StoredFile(url: url, fileName: fileName);
    } on StorageException catch (e) {
      throw ServerFailure('Upload failed: ${e.message}');
    } catch (_) {
      throw const ServerFailure('Upload failed. Please try again.');
    }
  }

  // ── Local fallback (non-web) ────────────────────────────────────────────────

  Future<StoredFile> _persistLocally({
    required String recordId,
    required String fileName,
    required Uint8List bytes,
    required String ext,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/records/$recordId');
    if (!await dir.exists()) await dir.create(recursive: true);
    final String dest =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final File created = await File(dest).writeAsBytes(bytes);
    return StoredFile(url: created.path, fileName: fileName);
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

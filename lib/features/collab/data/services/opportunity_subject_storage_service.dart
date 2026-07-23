import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';

/// Uploads opportunity-subject photos/documents to the Supabase Storage
/// `opportunity-subjects` bucket, falling back to a persisted local copy on
/// mobile/desktop when Supabase isn't configured.
///
/// Mirrors [RoleVerificationStorageService]'s conventions
/// (`<uid>/<opportunityId>/<timestamp>.<ext>`).
class OpportunitySubjectStorageService {
  OpportunitySubjectStorageService();

  static const String bucket = 'opportunity-subjects';

  Future<String> uploadFile({
    required String opportunityId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const ServerFailure('Selected file could not be read.');
    }
    final String ext = _extension(fileName);

    if (SupabaseConfig.isReady) {
      return _uploadToSupabase(
        opportunityId: opportunityId,
        bytes: bytes,
        ext: ext,
      );
    }
    if (kIsWeb) {
      throw const ServerFailure('Connect Supabase to upload files on the web.');
    }
    return _persistLocally(
      opportunityId: opportunityId,
      bytes: bytes,
      ext: ext,
    );
  }

  Future<String> _uploadToSupabase({
    required String opportunityId,
    required Uint8List bytes,
    required String ext,
  }) async {
    try {
      final client = SupabaseConfig.client;
      final String userId = client.auth.currentUser?.id ?? 'anon';
      final String objectPath =
          '$userId/$opportunityId/${DateTime.now().microsecondsSinceEpoch}.$ext';

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

  Future<String> _persistLocally({
    required String opportunityId,
    required Uint8List bytes,
    required String ext,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      '${docs.path}/opportunity_subjects/$opportunityId',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final String dest =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final File created = await File(dest).writeAsBytes(bytes);
    return created.path;
  }

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
      default:
        return 'application/octet-stream';
    }
  }
}

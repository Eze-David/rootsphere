import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

/// Result of an OCR extraction attempt.
class OcrResult {
  const OcrResult({this.text, this.available = true, this.message});

  /// Extracted text (null when nothing was found or OCR is unavailable).
  final String? text;

  /// False when OCR cannot run at all (Supabase not configured / function not
  /// deployed) so callers can fall back to manual entry without showing an
  /// error.
  final bool available;

  /// Optional human-readable note (e.g. why extraction failed).
  final String? message;

  bool get hasText => (text ?? '').trim().isNotEmpty;
}

/// Cross-platform OCR via the Supabase Edge Function `ocr`
/// (see supabase/functions/ocr). Running OCR server-side keeps a single code
/// path across web and mobile and avoids bundling native ML Kit binaries.
///
/// Degrades gracefully: when Supabase isn't configured or the function isn't
/// deployed, [extractText] returns an unavailable result rather than throwing,
/// so the upload flow still works with manual transcription.
class OcrService {
  OcrService();

  /// Sends the stored attachment reference to the edge function and returns the
  /// recognised text. [fileUrl] should be a public URL the function can fetch.
  Future<OcrResult> extractText({required String fileUrl}) async {
    if (!SupabaseConfig.isReady || !fileUrl.startsWith('http')) {
      return const OcrResult(
        available: false,
        message: 'OCR runs server-side; connect Supabase to enable it.',
      );
    }
    try {
      final FunctionResponse res = await SupabaseConfig.client.functions.invoke(
        'ocr',
        body: <String, dynamic>{'fileUrl': fileUrl},
      );
      if (res.status != 200) {
        return OcrResult(
          available: false,
          message: 'OCR service returned ${res.status}.',
        );
      }
      final dynamic data = res.data;
      final String? text = data is Map<String, dynamic>
          ? data['text'] as String?
          : data?.toString();
      return OcrResult(text: text);
    } on FunctionException catch (e) {
      // Function not deployed yet (404) or other invocation error.
      return OcrResult(
        available: false,
        message: 'OCR unavailable (${e.status}).',
      );
    } catch (_) {
      return const OcrResult(
        available: false,
        message: 'Could not reach the OCR service.',
      );
    }
  }
}

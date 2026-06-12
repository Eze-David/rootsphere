import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Renders an image from either a network URL (`http…`) or a local file path.
///
/// Used for person photos, which may be Supabase public URLs or locally
/// persisted files depending on whether Supabase is configured.
class AdaptiveImage extends StatelessWidget {
  const AdaptiveImage({
    super.key,
    required this.reference,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String reference;
  final double? width;
  final double? height;
  final BoxFit fit;

  bool get _isNetwork => reference.startsWith('http') || reference.startsWith('blob:');

  @override
  Widget build(BuildContext context) {
    final Widget errorWidget = Container(
      width: width,
      height: height,
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
    );

    if (_isNetwork) {
      return Image.network(
        reference,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => errorWidget,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: AppColors.surface,
            alignment: Alignment.center,
            child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    // Local file paths are only valid on non-web platforms.
    if (kIsWeb) return errorWidget;
    return Image.file(
      File(reference),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => errorWidget,
    );
  }
}

/// A circular avatar variant that falls back to a person icon.
class AdaptiveAvatar extends StatelessWidget {
  const AdaptiveAvatar({
    super.key,
    required this.reference,
    required this.radius,
  });

  final String? reference;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (reference == null || reference!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.cream,
        child: Icon(Icons.person, size: radius, color: AppColors.primary),
      );
    }
    return ClipOval(
      child: AdaptiveImage(
        reference: reference!,
        width: radius * 2,
        height: radius * 2,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../collab/presentation/providers/role_verification_providers.dart';
import '../../../tree/presentation/widgets/video_player_screen.dart';
import '../../domain/entities/watch_item.dart';
import '../providers/watch_providers.dart';

/// Home dashboard's "What to watch" strip (Ancestry-style): a horizontal row
/// of admin-curated photo/video cards. Every signed-in user can view it;
/// only platform admins see the "add" control and can upload.
class WhatToWatchSection extends ConsumerWidget {
  const WhatToWatchSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<WatchItem> items =
        ref.watch(watchItemsProvider).value ?? const <WatchItem>[];
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;

    if (items.isEmpty && !isAdmin) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.smart_display_outlined, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'What to watch',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (isAdmin)
              IconButton(
                onPressed: () => _showAddSheet(context),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add photo or video',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Text(
            'No videos or photos yet — tap + to add the first one.',
            style: text.bodyMedium,
          )
        else
          _WatchCarousel(items: items, isAdmin: isAdmin),
      ],
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (_) => const _AddWatchItemSheet(),
    );
  }
}

class _WatchCarousel extends ConsumerStatefulWidget {
  const _WatchCarousel({required this.items, required this.isAdmin});
  final List<WatchItem> items;
  final bool isAdmin;

  @override
  ConsumerState<_WatchCarousel> createState() => _WatchCarouselState();
}

class _WatchCarouselState extends ConsumerState<_WatchCarousel> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const double _cardWidth = 200;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final ScrollPosition pos = _controller.position;
    final bool left = pos.pixels > pos.minScrollExtent + 1;
    final bool right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    final double target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: Stack(
        children: <Widget>[
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) => SizedBox(
              width: _cardWidth,
              child: _WatchCard(item: widget.items[i], isAdmin: widget.isAdmin),
            ),
          ),
          if (_canScrollLeft)
            _NavArrow(
              alignment: Alignment.centerLeft,
              icon: Icons.chevron_left,
              onTap: () => _scrollBy(-_cardWidth - AppSpacing.md),
            ),
          if (_canScrollRight)
            _NavArrow(
              alignment: Alignment.centerRight,
              icon: Icons.chevron_right,
              onTap: () => _scrollBy(_cardWidth + AppSpacing.md),
            ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.alignment,
    required this.icon,
    required this.onTap,
  });
  final Alignment alignment;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}

class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.item, required this.isAdmin});
  final WatchItem item;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => _open(context),
      onLongPress: isAdmin ? () => _confirmDelete(context, ref) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AdaptiveImage(reference: item.displayThumbnail),
                  if (item.mediaType == WatchMediaType.video) ...<Widget>[
                    Container(color: Colors.black.withValues(alpha: 0.18)),
                    Center(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (item.category.isNotEmpty)
            Text(
              item.category,
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            item.title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    switch (item.mediaType) {
      case WatchMediaType.image:
        showFullscreenImage(context, item.mediaUrl);
        break;
      case WatchMediaType.video:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(reference: item.mediaUrl),
          ),
        );
        break;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this item?'),
        content: Text('"${item.title}" will be removed for everyone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(watchRepositoryProvider).deleteItem(item.id);
    final storage = ref.read(watchStorageServiceProvider);
    await storage.deleteMedia(item.mediaUrl);
    if (item.thumbnailUrl != null) await storage.deleteMedia(item.thumbnailUrl!);
  }
}

/// Admin-only "add photo or video" bottom sheet: pick a media type, pick the
/// file (plus a cover image for videos), fill in the category/title, upload.
class _AddWatchItemSheet extends ConsumerStatefulWidget {
  const _AddWatchItemSheet();

  @override
  ConsumerState<_AddWatchItemSheet> createState() => _AddWatchItemSheetState();
}

class _AddWatchItemSheetState extends ConsumerState<_AddWatchItemSheet> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  WatchMediaType _type = WatchMediaType.image;
  XFile? _media;
  XFile? _thumbnail;
  bool _submitting = false;

  @override
  void dispose() {
    _categoryController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _media != null &&
      (_type == WatchMediaType.image || _thumbnail != null) &&
      _titleController.text.trim().isNotEmpty;

  Future<void> _pickMedia() async {
    final XFile? file = _type == WatchMediaType.image
        ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null) setState(() => _media = file);
  }

  Future<void> _pickThumbnail() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null) setState(() => _thumbnail = file);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final String id = 'watch_${DateTime.now().microsecondsSinceEpoch}';
      final storage = ref.read(watchStorageServiceProvider);
      final String mediaUrl = await storage.uploadMedia(
        itemId: id,
        file: _media!,
      );
      final String? thumbnailUrl = _type == WatchMediaType.video
          ? await storage.uploadMedia(itemId: id, file: _thumbnail!)
          : null;
      await ref.read(watchRepositoryProvider).upsertItem(
        WatchItem(
          id: id,
          mediaType: _type,
          mediaUrl: mediaUrl,
          thumbnailUrl: thumbnailUrl,
          category: _categoryController.text.trim(),
          title: _titleController.text.trim(),
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final String msg = e is Failure ? e.message : 'Could not add this item.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Add to What to watch', style: text.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<WatchMediaType>(
              segments: const <ButtonSegment<WatchMediaType>>[
                ButtonSegment<WatchMediaType>(
                  value: WatchMediaType.image,
                  label: Text('Photo'),
                  icon: Icon(Icons.image_outlined),
                ),
                ButtonSegment<WatchMediaType>(
                  value: WatchMediaType.video,
                  label: Text('Video'),
                  icon: Icon(Icons.videocam_outlined),
                ),
              ],
              selected: <WatchMediaType>{_type},
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() {
                      _type = s.first;
                      _media = null;
                      _thumbnail = null;
                    }),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickMedia,
              icon: const Icon(Icons.upload_outlined),
              label: Text(
                _media == null
                    ? (_type == WatchMediaType.image ? 'Choose photo' : 'Choose video')
                    : 'Selected: ${_media!.name}',
              ),
            ),
            if (_type == WatchMediaType.video) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickThumbnail,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _thumbnail == null
                      ? 'Choose cover image'
                      : 'Cover: ${_thumbnail!.name}',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _categoryController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. Family stories',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _titleController,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Connecting to millions',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

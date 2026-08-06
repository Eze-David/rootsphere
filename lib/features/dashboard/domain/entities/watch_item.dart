/// Whether a "What to watch" card is a still photo or a video.
enum WatchMediaType { image, video }

/// A single admin-curated card in the Home dashboard's "What to watch" strip
/// (brief-inspired by Ancestry's "What to watch"): a photo or a video with a
/// small category label and a title, shown to every signed-in user.
class WatchItem {
  const WatchItem({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.category,
    required this.title,
    this.sortOrder = 0,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final WatchMediaType mediaType;

  /// The photo, or the uploaded video file.
  final String mediaUrl;

  /// Cover image for a video card; null for images (the image is its own
  /// thumbnail).
  final String? thumbnailUrl;

  final String category;
  final String title;
  final int sortOrder;
  final String? createdBy;
  final DateTime? createdAt;

  /// The image to render for this card's thumbnail.
  String get displayThumbnail => thumbnailUrl ?? mediaUrl;

  factory WatchItem.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return WatchItem(
      id: json['id'] as String,
      mediaType: (json['media_type'] as String?) == 'video'
          ? WatchMediaType.video
          : WatchMediaType.image,
      mediaUrl: json['media_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      category: json['category'] as String? ?? '',
      title: json['title'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdBy: json['created_by'] as String?,
      createdAt: parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'media_type': mediaType.name,
    'media_url': mediaUrl,
    'thumbnail_url': thumbnailUrl,
    'category': category,
    'title': title,
    'sort_order': sortOrder,
    'created_by': createdBy,
    'created_at': createdAt?.toIso8601String(),
  };
}

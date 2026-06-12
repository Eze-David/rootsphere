/// A single dated life event shown on a person's timeline (brief §Phase 2).
enum LifeEventType { birth, baptism, marriage, residence, occupation, death, custom }

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.type,
    required this.title,
    this.date,
    this.place,
    this.description,
  });

  final String id;
  final LifeEventType type;
  final String title;
  final DateTime? date;
  final String? place;
  final String? description;

  TimelineEvent copyWith({
    String? title,
    LifeEventType? type,
    DateTime? date,
    String? place,
    String? description,
  }) {
    return TimelineEvent(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      date: date ?? this.date,
      place: place ?? this.place,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'title': title,
    'date': date?.toIso8601String(),
    'place': place,
    'description': description,
  };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      id: json['id'] as String,
      type: LifeEventType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => LifeEventType.custom,
      ),
      title: json['title'] as String? ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      place: json['place'] as String?,
      description: json['description'] as String?,
    );
  }
}

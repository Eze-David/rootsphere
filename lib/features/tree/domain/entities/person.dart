import 'timeline_event.dart';

enum Sex { male, female, unknown }

/// A single individual in a family tree.
///
/// Relationships are modelled by id references so the graph can be rebuilt
/// without nested objects:
///  * [parentIds]  — up to two biological/adoptive parents.
///  * [spouseIds]  — one or more partners (symmetric; both sides store each other).
/// Children are derived by querying persons whose [parentIds] contain this id.
class Person {
  const Person({
    required this.id,
    required this.treeId,
    required this.givenName,
    this.surname = '',
    this.otherNames,
    this.nickname,
    this.suffix,
    this.sex = Sex.unknown,
    this.birthDate,
    this.deathDate,
    this.birthPlace,
    this.deathPlace,
    this.photoUrl,
    this.notes,
    this.parentIds = const <String>[],
    this.spouseIds = const <String>[],
    this.events = const <TimelineEvent>[],
    this.photoGallery = const <String>[],
  });

  final String id;
  final String treeId;
  final String givenName;
  final String surname;
  final String? otherNames;
  final String? nickname;
  final String? suffix;
  final Sex sex;
  final DateTime? birthDate;
  final DateTime? deathDate;
  final String? birthPlace;
  final String? deathPlace;
  final String? photoUrl;
  final String? notes;
  final List<String> parentIds;
  final List<String> spouseIds;
  final List<TimelineEvent> events;
  final List<String> photoGallery;

  bool get isLiving => deathDate == null;

  String get fullName {
    final String base = surname.isEmpty ? givenName : '$givenName $surname'.trim();
    if (suffix != null && suffix!.trim().isNotEmpty) {
      return '$base, ${suffix!.trim()}';
    }
    return base;
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String fmtDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "12 Mar 1918 – 15 Jun 1989" or "12 Mar 1986 –" for the living.
  /// Empty when no dates are known.
  String get lifespan {
    final String birth = birthDate != null ? fmtDate(birthDate!) : '';
    final String death = deathDate != null ? fmtDate(deathDate!) : '';
    if (birth.isEmpty && death.isEmpty) return '';
    return '$birth – $death';
  }

  Person copyWith({
    String? givenName,
    String? surname,
    Object? otherNames = _sentinel,
    Object? nickname = _sentinel,
    Object? suffix = _sentinel,
    Sex? sex,
    Object? birthDate = _sentinel,
    Object? deathDate = _sentinel,
    Object? birthPlace = _sentinel,
    Object? deathPlace = _sentinel,
    Object? photoUrl = _sentinel,
    Object? notes = _sentinel,
    List<String>? parentIds,
    List<String>? spouseIds,
    List<TimelineEvent>? events,
    List<String>? photoGallery,
  }) {
    return Person(
      id: id,
      treeId: treeId,
      givenName: givenName ?? this.givenName,
      surname: surname ?? this.surname,
      otherNames:
          otherNames == _sentinel ? this.otherNames : otherNames as String?,
      nickname:
          nickname == _sentinel ? this.nickname : nickname as String?,
      suffix: suffix == _sentinel ? this.suffix : suffix as String?,
      sex: sex ?? this.sex,
      birthDate: birthDate == _sentinel ? this.birthDate : birthDate as DateTime?,
      deathDate: deathDate == _sentinel ? this.deathDate : deathDate as DateTime?,
      birthPlace:
          birthPlace == _sentinel ? this.birthPlace : birthPlace as String?,
      deathPlace:
          deathPlace == _sentinel ? this.deathPlace : deathPlace as String?,
      photoUrl: photoUrl == _sentinel ? this.photoUrl : photoUrl as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      parentIds: parentIds ?? this.parentIds,
      spouseIds: spouseIds ?? this.spouseIds,
      events: events ?? this.events,
      photoGallery: photoGallery ?? this.photoGallery,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'treeId': treeId,
    'givenName': givenName,
    'surname': surname,
    'otherNames': otherNames,
    'nickname': nickname,
    'suffix': suffix,
    'sex': sex.name,
    'birthDate': birthDate?.toIso8601String(),
    'deathDate': deathDate?.toIso8601String(),
    'birthPlace': birthPlace,
    'deathPlace': deathPlace,
    'photoUrl': photoUrl,
    'notes': notes,
    'parentIds': parentIds,
    'spouseIds': spouseIds,
    'events': events.map((e) => e.toJson()).toList(),
    'photoGallery': photoGallery,
  };

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String,
      treeId: json['treeId'] as String,
      givenName: json['givenName'] as String? ?? '',
      surname: json['surname'] as String? ?? '',
      otherNames: json['otherNames'] as String?,
      nickname: json['nickname'] as String?,
      suffix: json['suffix'] as String?,
      sex: Sex.values.firstWhere(
        (s) => s.name == json['sex'],
        orElse: () => Sex.unknown,
      ),
      birthDate: json['birthDate'] != null
          ? DateTime.tryParse(json['birthDate'] as String)
          : null,
      deathDate: json['deathDate'] != null
          ? DateTime.tryParse(json['deathDate'] as String)
          : null,
      birthPlace: json['birthPlace'] as String?,
      deathPlace: json['deathPlace'] as String?,
      photoUrl: json['photoUrl'] as String?,
      notes: json['notes'] as String?,
      parentIds:
          (json['parentIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e as String)
              .toList(),
      spouseIds:
          (json['spouseIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e as String)
              .toList(),
      events:
          (json['events'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
              .toList(),
      photoGallery:
          (json['photoGallery'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e as String)
              .toList(),
    );
  }

  static const Object _sentinel = Object();
}

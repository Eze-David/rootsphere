import 'dart:math';

import 'timeline_event.dart';

enum Sex { male, female, unknown }

/// The kind of media a stored reference points at, derived from its file
/// extension. Drives how the gallery renders and plays each item.
enum MediaKind { image, video, audio, other }

/// Classifies a media reference (URL or path) by its file extension.
MediaKind mediaKindOf(String reference) {
  final String lower = reference.toLowerCase();
  final int q = lower.indexOf('?');
  final String clean = q >= 0 ? lower.substring(0, q) : lower;
  final int dot = clean.lastIndexOf('.');
  final String ext = dot >= 0 ? clean.substring(dot + 1) : '';
  const Set<String> images = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'bmp',
  };
  const Set<String> videos = <String>{
    'mp4',
    'mov',
    'm4v',
    'webm',
    'avi',
    'mkv',
    '3gp',
  };
  const Set<String> audios = <String>{
    'm4a',
    'aac',
    'mp3',
    'wav',
    'ogg',
    'caf',
    'opus',
  };
  if (images.contains(ext)) return MediaKind.image;
  if (videos.contains(ext)) return MediaKind.video;
  if (audios.contains(ext)) return MediaKind.audio;
  return MediaKind.other;
}

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
    this.code,
    this.surname = '',
    this.prefix,
    this.otherNames,
    this.nickname,
    this.suffix,
    this.sex = Sex.unknown,
    this.birthDate,
    this.deathDate,
    this.birthPlace,
    this.deathPlace,
    this.religion,
    this.city,
    this.stateProvince,
    this.region,
    this.country,
    this.education,
    this.language,
    this.occupation,
    this.researchNotes,
    this.researchQuestions,
    this.photoUrl,
    this.notes,
    this.parentIds = const <String>[],
    this.spouseIds = const <String>[],
    this.events = const <TimelineEvent>[],
    this.photoGallery = const <String>[],
    this.videoGallery = const <String>[],
    this.voiceNotes = const <String>[],
  });

  final String id;
  final String treeId;
  final String givenName;

  /// A short, human-shareable identifier generated once when the person is
  /// created (see [generateCode]) — shown on their profile and tree card.
  /// Null for people added before this field existed.
  final String? code;
  final String surname;

  /// A title placed before the name, e.g. "Chief", "Dr.", "Alhaji", "Otunba".
  final String? prefix;
  final String? otherNames;
  final String? nickname;
  final String? suffix;
  final Sex sex;
  final DateTime? birthDate;
  final DateTime? deathDate;
  final String? birthPlace;
  final String? deathPlace;

  /// The person's religion / faith.
  final String? religion;

  /// Residence / origin location, entered as separate components.
  final String? city;
  final String? stateProvince;
  final String? region;
  final String? country;

  /// Education and native/primary language.
  final String? education;
  final String? language;

  /// Occupation or profession.
  final String? occupation;

  /// Research notes and open questions for this person.
  final String? researchNotes;
  final String? researchQuestions;

  final String? photoUrl;
  final String? notes;
  final List<String> parentIds;
  final List<String> spouseIds;
  final List<TimelineEvent> events;
  final List<String> photoGallery;

  /// Video attachments (references suitable for the video player).
  final List<String> videoGallery;

  /// Recorded voice-note attachments (audio references).
  final List<String> voiceNotes;

  bool get isLiving => deathDate == null;

  String get fullName {
    final String core = surname.isEmpty
        ? givenName
        : '$givenName $surname'.trim();
    final String base = (prefix != null && prefix!.trim().isNotEmpty)
        ? '${prefix!.trim()} $core'.trim()
        : core;
    if (suffix != null && suffix!.trim().isNotEmpty) {
      return '$base, ${suffix!.trim()}';
    }
    return base;
  }

  /// A random 6-character code (e.g. "3F9K2A") for a newly created person.
  /// Excludes visually-confusable characters (0/O, 1/I/L) since this is
  /// meant to be read and typed by a person, not just stored. Not
  /// cryptographically unique, but at 32^6 (~1.07 billion) combinations
  /// collisions are negligible for a family tree's scale — the database
  /// still enforces uniqueness as a backstop (see migration
  /// 20260722000000_person_code.sql).
  static String generateCode() {
    const String charset = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
    final Random random = Random.secure();
    return List<String>.generate(
      6,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
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

  /// A single readable line of the residence components, e.g.
  /// "Enugu, Enugu State, South East, Nigeria". Empty when none are set.
  String get location {
    final List<String> parts = <String>[
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
      if ((stateProvince ?? '').trim().isNotEmpty) stateProvince!.trim(),
      if ((region ?? '').trim().isNotEmpty) region!.trim(),
      if ((country ?? '').trim().isNotEmpty) country!.trim(),
    ];
    return parts.join(', ');
  }

  Person copyWith({
    String? givenName,
    Object? code = _sentinel,
    String? surname,
    Object? prefix = _sentinel,
    Object? otherNames = _sentinel,
    Object? nickname = _sentinel,
    Object? suffix = _sentinel,
    Sex? sex,
    Object? birthDate = _sentinel,
    Object? deathDate = _sentinel,
    Object? birthPlace = _sentinel,
    Object? deathPlace = _sentinel,
    Object? religion = _sentinel,
    Object? city = _sentinel,
    Object? stateProvince = _sentinel,
    Object? region = _sentinel,
    Object? country = _sentinel,
    Object? education = _sentinel,
    Object? language = _sentinel,
    Object? occupation = _sentinel,
    Object? researchNotes = _sentinel,
    Object? researchQuestions = _sentinel,
    Object? photoUrl = _sentinel,
    Object? notes = _sentinel,
    List<String>? parentIds,
    List<String>? spouseIds,
    List<TimelineEvent>? events,
    List<String>? photoGallery,
    List<String>? videoGallery,
    List<String>? voiceNotes,
  }) {
    return Person(
      id: id,
      treeId: treeId,
      givenName: givenName ?? this.givenName,
      code: code == _sentinel ? this.code : code as String?,
      surname: surname ?? this.surname,
      prefix: prefix == _sentinel ? this.prefix : prefix as String?,
      otherNames: otherNames == _sentinel
          ? this.otherNames
          : otherNames as String?,
      nickname: nickname == _sentinel ? this.nickname : nickname as String?,
      suffix: suffix == _sentinel ? this.suffix : suffix as String?,
      sex: sex ?? this.sex,
      birthDate: birthDate == _sentinel
          ? this.birthDate
          : birthDate as DateTime?,
      deathDate: deathDate == _sentinel
          ? this.deathDate
          : deathDate as DateTime?,
      birthPlace: birthPlace == _sentinel
          ? this.birthPlace
          : birthPlace as String?,
      deathPlace: deathPlace == _sentinel
          ? this.deathPlace
          : deathPlace as String?,
      religion: religion == _sentinel ? this.religion : religion as String?,
      city: city == _sentinel ? this.city : city as String?,
      stateProvince: stateProvince == _sentinel
          ? this.stateProvince
          : stateProvince as String?,
      region: region == _sentinel ? this.region : region as String?,
      country: country == _sentinel ? this.country : country as String?,
      education: education == _sentinel ? this.education : education as String?,
      language: language == _sentinel ? this.language : language as String?,
      occupation: occupation == _sentinel
          ? this.occupation
          : occupation as String?,
      researchNotes: researchNotes == _sentinel
          ? this.researchNotes
          : researchNotes as String?,
      researchQuestions: researchQuestions == _sentinel
          ? this.researchQuestions
          : researchQuestions as String?,
      photoUrl: photoUrl == _sentinel ? this.photoUrl : photoUrl as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      parentIds: parentIds ?? this.parentIds,
      spouseIds: spouseIds ?? this.spouseIds,
      events: events ?? this.events,
      photoGallery: photoGallery ?? this.photoGallery,
      videoGallery: videoGallery ?? this.videoGallery,
      voiceNotes: voiceNotes ?? this.voiceNotes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'treeId': treeId,
    'givenName': givenName,
    'code': code,
    'surname': surname,
    'prefix': prefix,
    'otherNames': otherNames,
    'nickname': nickname,
    'suffix': suffix,
    'sex': sex.name,
    'birthDate': birthDate?.toIso8601String(),
    'deathDate': deathDate?.toIso8601String(),
    'birthPlace': birthPlace,
    'deathPlace': deathPlace,
    'religion': religion,
    'city': city,
    'stateProvince': stateProvince,
    'region': region,
    'country': country,
    'education': education,
    'language': language,
    'occupation': occupation,
    'researchNotes': researchNotes,
    'researchQuestions': researchQuestions,
    'photoUrl': photoUrl,
    'notes': notes,
    'parentIds': parentIds,
    'spouseIds': spouseIds,
    'events': events.map((e) => e.toJson()).toList(),
    'photoGallery': photoGallery,
    'videoGallery': videoGallery,
    'voiceNotes': voiceNotes,
  };

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String,
      treeId: json['treeId'] as String,
      givenName: json['givenName'] as String? ?? '',
      code: json['code'] as String?,
      surname: json['surname'] as String? ?? '',
      prefix: json['prefix'] as String?,
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
      religion: json['religion'] as String?,
      city: json['city'] as String?,
      stateProvince: json['stateProvince'] as String?,
      region: json['region'] as String?,
      country: json['country'] as String?,
      education: json['education'] as String?,
      language: json['language'] as String?,
      occupation: json['occupation'] as String?,
      researchNotes: json['researchNotes'] as String?,
      researchQuestions: json['researchQuestions'] as String?,
      photoUrl: json['photoUrl'] as String?,
      notes: json['notes'] as String?,
      parentIds: (json['parentIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
      spouseIds: (json['spouseIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
      events: (json['events'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      photoGallery:
          (json['photoGallery'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e as String)
              .toList(),
      videoGallery:
          (json['videoGallery'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e as String)
              .toList(),
      voiceNotes: (json['voiceNotes'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
    );
  }

  static const Object _sentinel = Object();
}

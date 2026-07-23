/// A privacy-safe person match returned by the global (cross-tree) search RPC
/// `search_persons_global`. Contains only the limited fields the function
/// exposes for people in trees the user may not belong to.
class GlobalPersonMatch {
  const GlobalPersonMatch({
    required this.id,
    required this.treeId,
    this.treeName,
    this.givenName = '',
    this.surname = '',
    this.birthYear,
    this.deathYear,
    this.birthPlace,
  });

  final String id;
  final String treeId;
  final String? treeName;
  final String givenName;
  final String surname;
  final int? birthYear;
  final int? deathYear;
  final String? birthPlace;

  String get fullName {
    final String name = '$givenName $surname'.trim();
    return name.isEmpty ? 'Unknown' : name;
  }

  String get lifespan {
    if (birthYear == null && deathYear == null) return '';
    return '${birthYear ?? '?'} – ${deathYear ?? ''}'.trim();
  }

  /// "1918 – 1989 · Lagos · in Okonkwo"
  String get subtitle => <String>[
    if (lifespan.isNotEmpty) lifespan,
    if ((birthPlace ?? '').trim().isNotEmpty) birthPlace!.trim(),
    if ((treeName ?? '').trim().isNotEmpty) 'in ${treeName!.trim()}',
  ].join(' · ');

  factory GlobalPersonMatch.fromRow(Map<String, dynamic> row) {
    int? toInt(dynamic v) =>
        v == null ? null : (v is int ? v : int.tryParse(v.toString()));
    return GlobalPersonMatch(
      id: row['id'].toString(),
      treeId: row['tree_id'].toString(),
      treeName: row['tree_name'] as String?,
      givenName: row['given_name'] as String? ?? '',
      surname: row['surname'] as String? ?? '',
      birthYear: toInt(row['birth_year']),
      deathYear: toInt(row['death_year']),
      birthPlace: row['birth_place'] as String?,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/data/african_locations.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/global_person_card.dart';
import '../widgets/global_record_card.dart';
import '../widgets/historical_result_card.dart';
import '../widgets/records_library_hero.dart';
import '../../../profile/presentation/providers/family_tree_provider.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../domain/entities/global_person_match.dart';
import '../../domain/entities/global_record_match.dart';
import '../../domain/entities/historical_record.dart';
import '../../domain/entities/record.dart';
import '../providers/record_providers.dart';

/// FamilySearch-style "Search historical records" screen, scoped to a record
/// [type] chosen from the Records chips. Submitting the form queries the
/// external provider (via the `records-search` edge function) and lists matches
/// the user can open or save into their own records.
class HistoricalRecordsSearchScreen extends ConsumerStatefulWidget {
  const HistoricalRecordsSearchScreen({super.key, this.type});

  /// The record type to search, or null to search across all types.
  final RecordType? type;

  @override
  ConsumerState<HistoricalRecordsSearchScreen> createState() =>
      _HistoricalRecordsSearchScreenState();
}

class _HistoricalRecordsSearchScreenState
    extends ConsumerState<HistoricalRecordsSearchScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _place = TextEditingController();
  final _year = TextEditingController();

  String _country = 'Nigeria';
  String _birthPlace = '';

  bool _searching = false;
  bool _hasSearched = false;
  RecordSearchResult _result = const RecordSearchResult();
  final Set<String> _saved = <String>{};

  // Matches from the user's own data, across all of their trees.
  List<Person> _localPeople = const <Person>[];
  List<Record> _localRecords = const <Record>[];
  Map<String, String> _treeNames = const <String, String>{};

  // Matches from every other tree in the database (privacy-safe projection).
  List<GlobalPersonMatch> _globalMatches = const <GlobalPersonMatch>[];
  final Set<String> _joining = <String>{};

  // Unattached records anybody has uploaded — a community contribution not
  // tied to any specific tree's people, found via the same privacy-safe RPC
  // pattern as _globalMatches.
  List<GlobalRecordMatch> _globalRecordMatches = const <GlobalRecordMatch>[];
  final Set<String> _savedGlobalRecords = <String>{};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _place.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    final StringBuffer placeBuffer = StringBuffer(_country);
    if (_birthPlace.trim().isNotEmpty) {
      placeBuffer.write(', ${_birthPlace.trim()}');
    }
    if (_place.text.trim().isNotEmpty) {
      placeBuffer.write(', ${_place.text.trim()}');
    }
    final String place = placeBuffer.toString();
    // The external provider search gets the country folded into `place`
    // (FamilySearch-style collection scoping expects that). Our own database
    // — this tree, other trees, and community records — must NOT require it:
    // most stored birth/death places are just a city/state, not "<City>,
    // Nigeria", so ANDing the country in was silently zeroing out every local
    // and cross-tree match whenever it didn't literally contain the country
    // name. Only the explicitly-typed state/province + free-text place count
    // for those searches.
    final StringBuffer dbPlaceBuffer = StringBuffer();
    if (_birthPlace.trim().isNotEmpty) dbPlaceBuffer.write(_birthPlace.trim());
    if (_place.text.trim().isNotEmpty) {
      if (dbPlaceBuffer.isNotEmpty) dbPlaceBuffer.write(', ');
      dbPlaceBuffer.write(_place.text.trim());
    }
    final String dbPlace = dbPlaceBuffer.toString();

    final query = RecordSearchQuery(
      type: widget.type,
      firstName: _firstName.text,
      lastName: _lastName.text,
      place: place,
      year: int.tryParse(_year.text.trim()),
    );
    if (query.isEmpty) return;
    final RecordSearchQuery dbQuery = RecordSearchQuery(
      type: widget.type,
      firstName: _firstName.text,
      lastName: _lastName.text,
      place: dbPlace,
      year: int.tryParse(_year.text.trim()),
    );

    setState(() {
      _searching = true;
      _hasSearched = true;
    });

    // Search our own database across every tree the user belongs to.
    final List<Person> allPeople = await _allPeople();
    final List<Record> allRecords = await _allRecords();
    final Map<String, Person> peopleById = <String, Person>{
      for (final p in allPeople) p.id: p,
    };
    final List<Person> localPeople = _matchPeople(dbQuery, allPeople);
    final List<Record> localRecords = _matchRecords(
      dbQuery,
      allRecords,
      peopleById,
    );

    // Search every other tree in the database (cross-tree discovery), hiding
    // people already surfaced from the user's own trees.
    final Set<String> ownTrees = _allTreeIds();
    final Set<String> localIds = localPeople.map((p) => p.id).toSet();
    final List<GlobalPersonMatch> global =
        (await ref.read(globalPeopleServiceProvider).search(dbQuery))
            .where(
              (m) => !ownTrees.contains(m.treeId) && !localIds.contains(m.id),
            )
            .toList();

    // Community records: anybody's uploaded-but-unattached records, hiding
    // ones already surfaced from the user's own trees.
    final Set<String> localRecordIds = localRecords.map((r) => r.id).toSet();
    final List<GlobalRecordMatch> globalRecords =
        (await ref.read(globalRecordsServiceProvider).search(dbQuery))
            .where((m) => !localRecordIds.contains(m.id))
            .toList();

    final result = await ref
        .read(historicalRecordsServiceProvider)
        .search(query);
    if (mounted) {
      setState(() {
        _searching = false;
        _localPeople = localPeople;
        _localRecords = localRecords;
        _globalMatches = global;
        _globalRecordMatches = globalRecords;
        _result = result;
      });
    }
  }

  Future<void> _saveGlobalRecord(GlobalRecordMatch match) async {
    final String treeId = ref.read(activeTreeIdProvider);
    final Record record = Record(
      id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
      treeId: treeId,
      type: match.type,
      title: match.title,
      repository: match.repository,
      date: match.eventDate,
      fileUrl: match.fileUrl,
      fileName: match.fileName,
      ocrText: match.ocrText,
      createdAt: DateTime.now(),
    );
    await ref.read(recordRepositoryProvider).upsertRecord(record);
    if (mounted) {
      setState(() => _savedGlobalRecords.add(match.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${match.displayTitle}" to your records.'),
        ),
      );
    }
  }

  Future<void> _join(GlobalPersonMatch match) async {
    setState(() => _joining.add(match.treeId));
    try {
      await ref
          .read(familyTreeControllerProvider.notifier)
          .joinTree(match.treeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined "${match.treeName ?? 'tree'}".')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join that tree.')),
        );
      }
    } finally {
      if (mounted) setState(() => _joining.remove(match.treeId));
    }
  }

  // ── Local (our database) matching ──────────────────────────────────────────

  /// All tree ids the user can search: every linked tree plus the active one.
  Set<String> _allTreeIds() {
    final trees =
        ref.read(familyTreeControllerProvider).value ?? const <dynamic>[];
    return <String>{
      ref.read(activeTreeIdProvider),
      for (final t in trees) t.id as String,
    };
  }

  /// Fetches and aggregates people from all of the user's trees, recording each
  /// tree's display name for disambiguation in the results.
  Future<List<Person>> _allPeople() async {
    final Set<String> ids = _allTreeIds();
    final trees =
        ref.read(familyTreeControllerProvider).value ?? const <dynamic>[];
    _treeNames = <String, String>{
      for (final t in trees) t.id as String: t.name as String,
    };
    final repo = ref.read(treeRepositoryProvider);
    final lists = await Future.wait(ids.map(repo.getPersons));
    return <Person>[for (final l in lists) ...l];
  }

  /// Fetches and aggregates records from all of the user's trees.
  Future<List<Record>> _allRecords() async {
    final Set<String> ids = _allTreeIds();
    final repo = ref.read(recordRepositoryProvider);
    final lists = await Future.wait(ids.map(repo.getRecords));
    return <Record>[for (final l in lists) ...l];
  }

  /// Opens a person/record that may live in a different tree: switch the
  /// active tree first so the detail screens (which read the active tree)
  /// resolve it, then switch back once that screen is closed.
  ///
  /// This override is otherwise permanent and persisted to disk (see
  /// [setSelectedTreeId]) — without restoring it here, browsing someone
  /// else's record from this cross-tree view would silently leave the
  /// viewer's own uploads/edits targeting that other tree from then on,
  /// which then fail row-level security if they aren't actually a member of
  /// it (e.g. an admin/reviewer who can see but not write to it).
  Future<void> _openLocal(String treeId, String route) async {
    final String? previous = ref.read(selectedTreeIdProvider);
    final bool switching = ref.read(activeTreeIdProvider) != treeId;
    if (switching) {
      setSelectedTreeId(ref, treeId);
      ref.read(focusPersonIdProvider.notifier).state = null;
    }
    await context.push(route);
    if (switching && mounted) {
      setSelectedTreeId(ref, previous);
    }
  }

  String _treeLabel(String treeId) {
    final String? name = _treeNames[treeId];
    if (name != null && name.isNotEmpty) return name;
    if (treeId == 'okonkwo') return 'Okonkwo';
    if (treeId.startsWith('t_')) return 'My Family Tree';
    return 'Tree';
  }

  /// People across all trees matching the query (name / year / place).
  List<Person> _matchPeople(RecordSearchQuery q, List<Person> people) {
    final String first = q.firstName.trim().toLowerCase();
    final String last = q.lastName.trim().toLowerCase();
    final String place = q.place.trim().toLowerCase();

    return people.where((p) {
      if (first.isNotEmpty &&
          !p.givenName.toLowerCase().contains(first) &&
          !(p.nickname ?? '').toLowerCase().contains(first)) {
        return false;
      }
      if (last.isNotEmpty && !p.surname.toLowerCase().contains(last)) {
        return false;
      }
      if (q.year != null &&
          p.birthDate?.year != q.year &&
          p.deathDate?.year != q.year) {
        return false;
      }
      if (place.isNotEmpty &&
          !(p.birthPlace ?? '').toLowerCase().contains(place) &&
          !(p.deathPlace ?? '').toLowerCase().contains(place)) {
        return false;
      }
      // Require at least one provided criterion to have matched something.
      return first.isNotEmpty ||
          last.isNotEmpty ||
          place.isNotEmpty ||
          q.year != null;
    }).toList();
  }

  /// Records in the active tree matching the query.
  /// Records across all trees matching the query.
  /// Ranks by closeness rather than requiring every field to match — a
  /// document you couldn't title properly (e.g. a photographed certificate)
  /// is still findable as long as the searched name/place/year shows up
  /// anywhere in it, including its OCR'd text, not just the title/notes.
  /// Records matching more of the search's terms rank above ones matching
  /// only one, instead of an all-or-nothing filter.
  List<Record> _matchRecords(
    RecordSearchQuery q,
    List<Record> records,
    Map<String, Person> people,
  ) {
    final List<String> terms = <String>[
      q.firstName.trim(),
      q.lastName.trim(),
      q.place.trim(),
      if (q.year != null) '${q.year}',
    ].where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
    if (terms.isEmpty) return const <Record>[];

    final List<(Record, int)> scored = <(Record, int)>[];
    for (final r in records) {
      if (q.type != null && r.type != q.type) continue;
      final String haystack = <String>[
        r.title,
        r.repository,
        r.notes ?? '',
        r.ocrText ?? '',
        for (final id in r.personIds) people[id]?.fullName ?? '',
      ].join(' ').toLowerCase();

      int score = 0;
      for (final term in terms) {
        if (haystack.contains(term)) score++;
      }
      // The record's own structured date field matching the searched year
      // is a stronger signal than that year merely appearing somewhere in
      // free text, so it's weighted extra.
      if (q.year != null && r.year == q.year) score++;
      if (score > 0) scored.add((r, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return <Record>[for (final (r, _) in scored) r];
  }

  Future<void> _save(HistoricalRecord hit) async {
    final String treeId = ref.read(activeTreeIdProvider);
    final Record record = Record(
      id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
      treeId: treeId,
      // For an all-types search, fall back to the result's own type.
      type: widget.type ?? hit.type,
      title: hit.name,
      repository: hit.collection ?? 'FamilySearch',
      date: _parseYear(hit.eventDate),
      notes: hit.subtitle,
      citationOverride: hit.sourceUrl,
      createdAt: DateTime.now(),
    );
    await ref.read(recordRepositoryProvider).upsertRecord(record);
    if (mounted) {
      setState(() => _saved.add(hit.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "${hit.name}" to your records.')),
      );
    }
  }

  DateTime? _parseYear(String? eventDate) {
    if (eventDate == null) return null;
    final match = RegExp(r'(\d{4})').firstMatch(eventDate);
    if (match == null) return null;
    return DateTime(int.parse(match.group(1)!));
  }

  /// Types with more than one curated hero photo auto-crossfade between
  /// them (see [RecordsLibraryHero]) — everything else is a single-element
  /// list, which the hero renders as a static image.
  List<String> _heroAssets() {
    switch (widget.type) {
      case RecordType.birth:
        return const <String>[
          'assets/images/records_birth_hero.jpg',
          'assets/images/records_birth_hero_2.jpg',
          'assets/images/records_birth_hero_3.jpeg',
        ];
      case RecordType.marriage:
        return const <String>[
          'assets/images/records_marriage_hero.jpg',
          'assets/images/records_marriage_hero_2.jpg',
          'assets/images/records_marriage_hero_3.jpg',
        ];
      case RecordType.death:
        return const <String>[
          'assets/images/records_death_hero.jpg',
          'assets/images/records_death_hero_2.jpg',
          'assets/images/records_death_hero_3.jpg',
          'assets/images/records_death_hero_4.jpg',
          'assets/images/records_death_hero_5.jpg',
        ];
      case RecordType.census:
        return const <String>[
          'assets/images/records_census_hero.jpg',
          'assets/images/records_census_hero_2.jpg',
          'assets/images/records_census_hero_3.jpg',
          'assets/images/records_census_hero_4.jpeg',
        ];
      case RecordType.military:
        return const <String>[
          'assets/images/records_military_hero.jpg',
          'assets/images/records_military_hero_2.jpg',
          'assets/images/records_military_hero_3.jpeg',
          'assets/images/records_military_hero_4.jpeg',
        ];
      case RecordType.immigration:
        return const <String>[
          'assets/images/records_immigration_hero.jpg',
          'assets/images/records_immigration_hero_2.jpg',
          'assets/images/records_immigration_hero_3.jpg',
          'assets/images/records_immigration_hero_4.jpeg',
        ];
      case RecordType.baptism:
        return const <String>[
          'assets/images/records_baptism_hero.jpg',
          'assets/images/records_baptism_hero_2.jpg',
          'assets/images/records_baptism_hero_3.jpg',
        ];
      case RecordType.photo:
        return const <String>[
          'assets/images/records_photo_hero.jpg',
          'assets/images/records_photo_hero_2.jpg',
          'assets/images/records_photo_hero_3.jpg',
          'assets/images/records_photo_hero_4.jpeg',
        ];
      case RecordType.newspaper:
        return const <String>[
          'assets/images/records_newspaper_hero.jpg',
          'assets/images/records_newspaper_hero_2.jpg',
          'assets/images/records_newspaper_hero_3.jpg',
        ];
      case RecordType.community:
        return const <String>[
          'assets/images/records_community_hero.jpg',
          'assets/images/records_community_hero_2.jpg',
        ];
      case RecordType.cemetery:
        return const <String>[
          'assets/images/records_cemetery_hero.jpg',
          'assets/images/records_cemetery_hero_2.jpg',
        ];
      case RecordType.school:
        return const <String>[
          'assets/images/records_school_hero.jpg',
          'assets/images/records_school_hero_2.jpg',
        ];
      case RecordType.exam:
        return const <String>[
          'assets/images/records_exam_hero.jpg',
          'assets/images/records_exam_hero_2.jpeg',
        ];
      case RecordType.church:
        return const <String>[
          'assets/images/records_church_hero.jpg',
          'assets/images/records_church_hero_2.jpg',
          'assets/images/records_church_hero_3.jpeg',
        ];
      case RecordType.transportManifest:
        return const <String>[
          'assets/images/records_transport_manifest_hero.jpg',
          'assets/images/records_transport_manifest_hero_2.jpg',
          'assets/images/records_transport_manifest_hero_3.jpg',
        ];
      case RecordType.library:
        return const <String>['assets/images/records_library_hero.jpg'];
      case RecordType.museum:
        return const <String>[
          'assets/images/records_museum_hero.jpg',
          'assets/images/records_museum_hero_2.jpeg',
        ];
      case RecordType.archive:
        return const <String>[
          'assets/images/records_archive_hero.jpeg',
          'assets/images/records_archive_hero_2.jpeg',
          'assets/images/records_archive_hero_3.jpeg',
        ];
      case RecordType.landDocument:
        return const <String>[
          'assets/images/records_land_document_hero.jpg',
          'assets/images/records_land_document_hero_2.jpg',
          'assets/images/records_land_document_hero_3.jpg',
        ];
      case RecordType.will:
        return const <String>['assets/images/records_will_hero.jpg'];
      case RecordType.cooperativeAssociation:
        return const <String>['assets/images/records_community_hero.jpg'];
      case RecordType.politicalPartyRegister:
        return const <String>[
          'assets/images/records_political_party_hero.jpeg',
        ];
      case RecordType.okadaUnion:
        return const <String>['assets/images/records_okada_union_hero.jpg'];
      case RecordType.marketAssociation:
        return const <String>[
          'assets/images/records_market_association_hero.jpg',
          'assets/images/records_market_association_hero_2.jpeg',
          'assets/images/records_market_association_hero_3.jpeg',
        ];
      case RecordType.hospital:
        return const <String>[
          'assets/images/records_hospital_hero.jpg',
          'assets/images/records_hospital_hero_2.jpg',
          'assets/images/records_hospital_hero_3.jpg',
        ];
      case RecordType.flightManifest:
        return const <String>[
          'assets/images/records_flight_manifest_hero.jpg',
          'assets/images/records_flight_manifest_hero_2.jpg',
          'assets/images/records_flight_manifest_hero_3.jpg',
          'assets/images/records_flight_manifest_hero_4.jpeg',
        ];
      case RecordType.recruitmentAgency:
        return const <String>['assets/images/records_community_hero.jpg'];
      default:
        return const <String>['assets/images/records_search_hero.jpg'];
    }
  }

  String _heroTitle() {
    switch (widget.type) {
      case RecordType.birth:
        return 'Find birth records';
      case RecordType.marriage:
        return 'Find marriage records';
      case RecordType.death:
        return 'Find death records';
      case RecordType.census:
        return 'Find census records';
      case RecordType.military:
        return 'Find military records';
      case RecordType.immigration:
        return 'Find immigration records';
      case RecordType.baptism:
        return 'Find baptism records';
      case RecordType.photo:
        return 'Find photo records';
      case RecordType.newspaper:
        return 'Find newspaper records';
      case RecordType.community:
        return 'Find community records';
      case RecordType.cemetery:
        return 'Find cemetery records';
      case RecordType.school:
        return 'Find school records';
      case RecordType.exam:
        return 'Find exam records';
      case RecordType.church:
        return 'Find church records';
      case RecordType.transportManifest:
        return 'Find transportation manifests';
      case RecordType.library:
        return 'Find library records';
      case RecordType.museum:
        return 'Find museum records';
      case RecordType.archive:
        return 'Find archive records';
      case RecordType.landDocument:
        return 'Find land documents';
      case RecordType.will:
        return 'Find wills';
      case RecordType.cooperativeAssociation:
        return 'Find cooperative association records';
      case RecordType.politicalPartyRegister:
        return 'Find political party registers';
      case RecordType.okadaUnion:
        return 'Find Okada union records';
      case RecordType.marketAssociation:
        return 'Find market association records';
      case RecordType.hospital:
        return 'Find hospital records';
      case RecordType.flightManifest:
        return 'Find flight manifests';
      case RecordType.recruitmentAgency:
        return 'Find recruitment agency records';
      default:
        return 'Find your African ancestors';
    }
  }

  String _heroSubtitle() {
    switch (widget.type) {
      case RecordType.birth:
        return 'Search birth certificates, hospital registers, and vital records.';
      case RecordType.marriage:
        return 'Search marriage registrations, certificates, and family celebrations.';
      case RecordType.death:
        return 'Search death certificates, funeral records, and obituaries.';
      case RecordType.census:
        return 'Search census enumerations, population counts, and household records.';
      case RecordType.military:
        return 'Search military service records, draft registrations, and war memorials.';
      case RecordType.immigration:
        return 'Search passenger lists, visas, passports, and naturalization records.';
      case RecordType.baptism:
        return 'Search baptism certificates, christening records, and church registers.';
      case RecordType.photo:
        return 'Search family portraits, studio photos, and restored images.';
      case RecordType.newspaper:
        return 'Search newspaper clippings, obituaries, and historical announcements.';
      case RecordType.community:
        return 'Search community archives, public records, and local registries.';
      case RecordType.cemetery:
        return 'Search cemetery registers, burial records, and grave inscriptions.';
      case RecordType.school:
        return 'Search school registers, enrollment records, and yearbooks.';
      case RecordType.exam:
        return 'Search exam results, certificates, and academic transcripts.';
      case RecordType.church:
        return 'Search church registers, membership rolls, and parish records.';
      case RecordType.transportManifest:
        return 'Search ship, train, and airline passenger manifests.';
      case RecordType.library:
        return 'Search library catalogs, special collections, and local history rooms.';
      case RecordType.museum:
        return 'Search museum exhibits, artifact records, and curator notes.';
      case RecordType.archive:
        return 'Search national and regional archives, manuscripts, and government files.';
      case RecordType.landDocument:
        return 'Search deeds, land certificates, surveys, and property registries.';
      case RecordType.will:
        return 'Search wills, probate records, and estate distributions.';
      case RecordType.cooperativeAssociation:
        return 'Search cooperative society registers, membership, and meeting records.';
      case RecordType.politicalPartyRegister:
        return 'Search political party membership rolls and registration records.';
      case RecordType.okadaUnion:
        return 'Search Okada (motorcycle taxi) union membership and registration records.';
      case RecordType.marketAssociation:
        return 'Search market/trader association registers, membership, and dues records.';
      case RecordType.hospital:
        return 'Search hospital admission logs, birth registers, and medical records.';
      case RecordType.flightManifest:
        return 'Search airline passenger manifests and flight boarding records.';
      case RecordType.recruitmentAgency:
        return 'Search recruitment and employment agency registers and placement records.';
      default:
        return 'Search for names in African records, family trees, cemeteries, and oral histories.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          // The back button/title sit inside the scrolling hero (not a
          // persistent Scaffold app bar) so they scroll away with the rest
          // of the content instead of staying pinned at the top.
          Stack(
            children: <Widget>[
              RecordsLibraryHero(
                assets: _heroAssets(),
                title: _heroTitle(),
                subtitle: _heroSubtitle(),
              ),
              SafeArea(
                bottom: false,
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  title: const Text('Search records'),
                  foregroundColor: Colors.white,
                  titleTextStyle: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SearchCard(
                  firstNameController: _firstName,
                  lastNameController: _lastName,
                  yearController: _year,
                  selectedCountry: _country,
                  selectedBirthPlace: _birthPlace,
                  onCountryChanged: (v) => setState(() {
                    _country = v;
                    _birthPlace = '';
                  }),
                  onBirthPlaceChanged: (v) => setState(() => _birthPlace = v),
                  searching: _searching,
                  onSearch: _search,
                ),
                const SizedBox(height: AppSpacing.xl),
                ..._buildResults(text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResults(TextTheme text) {
    if (!_hasSearched || _searching) return const <Widget>[];

    final List<Widget> out = <Widget>[];
    final int localCount = _localPeople.length + _localRecords.length;

    // ── From your tree (our database) ───────────────────────────────────────
    out.add(Text('FROM YOUR TREES', style: text.labelSmall));
    out.add(const SizedBox(height: AppSpacing.sm));
    if (localCount == 0) {
      out.add(
        Text(
          'No matches in your trees.',
          style: text.bodyMedium,
        ),
      );
    } else {
      for (final p in _localPeople) {
        out.add(
          _LocalCard(
            icon: Icons.person_outline,
            title: p.fullName,
            subtitle: <String>[
              _treeLabel(p.treeId),
              if (p.lifespan.isNotEmpty) p.lifespan,
              if ((p.birthPlace ?? '').isNotEmpty) p.birthPlace!,
            ].join(' · '),
            badge: 'Person',
            onTap: () => _openLocal(p.treeId, '${AppRoutes.person}/${p.id}'),
          ),
        );
      }
      for (final r in _localRecords) {
        out.add(
          _LocalCard(
            icon: r.type.icon,
            title: r.displayTitle,
            subtitle: <String>[
              _treeLabel(r.treeId),
              if (r.subtitle.isNotEmpty) r.subtitle,
            ].join(' · '),
            badge: 'Record',
            onTap: () => _openLocal(r.treeId, '${AppRoutes.record}/${r.id}'),
          ),
        );
      }
    }

    // ── Across all trees (other members' trees) ─────────────────────────────
    out.add(const SizedBox(height: AppSpacing.xl));
    out.add(Text('ACROSS ALL TREES', style: text.labelSmall));
    out.add(const SizedBox(height: AppSpacing.sm));
    if (_globalMatches.isEmpty) {
      out.add(
        Text(
          'No matches in other trees.',
          style: text.bodyMedium,
        ),
      );
    } else {
      for (final m in _globalMatches) {
        out.add(
          GlobalPersonCard(
            match: m,
            joining: _joining.contains(m.treeId),
            onJoin: () => _join(m),
          ),
        );
      }
    }

    // ── Community records (anybody's unattached uploads) ────────────────────
    out.add(const SizedBox(height: AppSpacing.xl));
    out.add(Text('COMMUNITY RECORDS', style: text.labelSmall));
    out.add(const SizedBox(height: AppSpacing.sm));
    if (_globalRecordMatches.isEmpty) {
      out.add(
        Text(
          'No community-uploaded records match.',
          style: text.bodyMedium,
        ),
      );
    } else {
      for (final m in _globalRecordMatches) {
        out.add(
          GlobalRecordCard(
            match: m,
            saved: _savedGlobalRecords.contains(m.id),
            onSave: () => _saveGlobalRecord(m),
            onOpen: m.fileUrl == null ? null : () => _open(m.fileUrl!),
          ),
        );
      }
    }

    // ── Historical records (external provider) ──────────────────────────────
    out.add(const SizedBox(height: AppSpacing.xl));
    out.add(Text('HISTORICAL RECORDS', style: text.labelSmall));
    out.add(const SizedBox(height: AppSpacing.sm));
    if (!_result.available) {
      out.add(
        _Notice(
          icon: Icons.cloud_off_outlined,
          title: 'Search unavailable',
          message:
              _result.message ??
              'The records search service isn\u2019t reachable yet.',
        ),
      );
    } else if (_result.records.isEmpty) {
      out.add(
        _Notice(
          icon: Icons.search_off,
          title: 'No matches found',
          message: 'Try fewer details or a different spelling.',
        ),
      );
    } else {
      for (final hit in _result.records) {
        out.add(
          HistoricalResultCard(
            hit: hit,
            saved: _saved.contains(hit.id),
            onSave: () => _save(hit),
            onOpen: hit.sourceUrl == null ? null : () => _open(hit.sourceUrl!),
          ),
        );
      }
    }

    return out;
  }

  Future<void> _open(String url) async {
    final Uri uri = Uri.parse(url);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the source link.')),
      );
    }
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.firstNameController,
    required this.lastNameController,
    required this.yearController,
    required this.selectedCountry,
    required this.selectedBirthPlace,
    required this.onCountryChanged,
    required this.onBirthPlaceChanged,
    required this.searching,
    required this.onSearch,
  });

  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController yearController;
  final String selectedCountry;
  final String selectedBirthPlace;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onBirthPlaceChanged;
  final bool searching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: theme.dividerColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CountryDropdown(
            value: selectedCountry,
            onChanged: (v) {
              onCountryChanged(v);
              onBirthPlaceChanged('');
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _BirthPlaceDropdown(
            country: selectedCountry,
            value: selectedBirthPlace,
            onChanged: onBirthPlaceChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: firstNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'First name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: lastNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: yearController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              hintText: 'Birth year (optional)',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: searching ? null : onSearch,
              icon: searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.search),
              label: const Text('SEARCH'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryDropdown extends StatelessWidget {
  const _CountryDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _countries = africanCountries;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        hintText: 'Select a country',
        prefixIcon: Icon(Icons.flag_outlined),
      ),
      items: _countries.map((String c) {
        return DropdownMenuItem<String>(value: c, child: Text(c));
      }).toList(),
      onChanged: (String? v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _BirthPlaceDropdown extends StatelessWidget {
  const _BirthPlaceDropdown({
    required this.country,
    required this.value,
    required this.onChanged,
  });

  final String country;
  final String value;
  final ValueChanged<String> onChanged;

  static List<String> _placesFor(String country) {
    final List<String> states =
        africanStatesProvinces[country] ?? const <String>[];
    final List<String> cities = africanMajorCities[country] ?? const <String>[];
    return <String>[...states, ...cities];
  }

  @override
  Widget build(BuildContext context) {
    final List<String> places = _placesFor(country);
    if (places.isEmpty) {
      return TextField(
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Birth place (state / province / city)',
          prefixIcon: Icon(Icons.location_on_outlined),
        ),
      );
    }
    final List<String> options = <String>['', ...places];
    return DropdownButtonFormField<String>(
      value: value.isEmpty ? null : value,
      isExpanded: true,
      decoration: const InputDecoration(
        hintText: 'Birth place (state / province / city)',
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
      items: options.map((String p) {
        return DropdownMenuItem<String>(
          value: p,
          child: Text(p.isEmpty ? 'Any place' : p),
        );
      }).toList(),
      onChanged: (String? v) => onChanged(v ?? ''),
    );
  }
}

/// A match from the user's own tree (a person or a saved record).
class _LocalCard extends StatelessWidget {
  const _LocalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: text.titleMedium),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(subtitle, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(badge, style: text.labelSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 44, color: text.bodySmall?.color),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center, style: text.bodyMedium),
        ],
      ),
    );
  }
}

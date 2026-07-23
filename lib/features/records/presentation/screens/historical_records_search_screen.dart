import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/data/african_locations.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
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

  /// Opens a person/record that may live in a different tree: switch the active
  /// tree first so the detail screens (which read the active tree) resolve it.
  void _openLocal(String treeId, String route) {
    if (ref.read(activeTreeIdProvider) != treeId) {
      setSelectedTreeId(ref, treeId);
      ref.read(focusPersonIdProvider.notifier).state = null;
    }
    context.push(route);
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
  List<Record> _matchRecords(
    RecordSearchQuery q,
    List<Record> records,
    Map<String, Person> people,
  ) {
    final String name = <String>[
      q.firstName.trim(),
      q.lastName.trim(),
    ].where((s) => s.isNotEmpty).join(' ').toLowerCase();
    final String place = q.place.trim().toLowerCase();

    return records.where((r) {
      if (q.type != null && r.type != q.type) return false;
      final String haystack = <String>[
        r.title,
        r.repository,
        r.notes ?? '',
        for (final id in r.personIds) people[id]?.fullName ?? '',
      ].join(' ').toLowerCase();
      if (name.isNotEmpty && !haystack.contains(name)) return false;
      if (place.isNotEmpty && !haystack.contains(place)) return false;
      if (q.year != null && r.year != q.year) return false;
      return name.isNotEmpty || place.isNotEmpty || q.year != null;
    }).toList();
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

  String _heroAsset() {
    switch (widget.type) {
      case RecordType.marriage:
        return 'assets/images/records_marriage_hero.png';
      case RecordType.death:
        return 'assets/images/records_death_hero.png';
      case RecordType.census:
        return 'assets/images/records_census_hero.png';
      case RecordType.military:
        return 'assets/images/records_military_hero.png';
      case RecordType.immigration:
        return 'assets/images/records_immigration_hero.png';
      case RecordType.baptism:
        return 'assets/images/records_baptism_hero.png';
      case RecordType.photo:
        return 'assets/images/records_photo_hero.png';
      case RecordType.newspaper:
        return 'assets/images/records_newspaper_hero.png';
      case RecordType.community:
        return 'assets/images/records_community_hero.png';
      case RecordType.cemetery:
        return 'assets/images/records_cemetery_hero.png';
      case RecordType.school:
        return 'assets/images/records_school_hero.png';
      case RecordType.exam:
        return 'assets/images/records_exam_hero.png';
      case RecordType.church:
        return 'assets/images/records_baptism_hero.png';
      case RecordType.transportManifest:
        return 'assets/images/records_immigration_hero.png';
      case RecordType.library:
        return 'assets/images/records_library_hero.png';
      case RecordType.museum:
        return 'assets/images/records_community_hero.png';
      case RecordType.archive:
        return 'assets/images/records_newspaper_hero.png';
      case RecordType.landDocument:
        return 'assets/images/records_cemetery_hero.png';
      case RecordType.will:
        return 'assets/images/records_exam_hero.png';
      case RecordType.cooperativeAssociation:
        return 'assets/images/records_community_hero.png';
      case RecordType.politicalPartyRegister:
        return 'assets/images/records_community_hero.png';
      case RecordType.okadaUnion:
        return 'assets/images/records_immigration_hero.png';
      default:
        return 'assets/images/records_search_hero.png';
    }
  }

  String _heroTitle() {
    switch (widget.type) {
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
      default:
        return 'Find your African ancestors';
    }
  }

  String _heroSubtitle() {
    switch (widget.type) {
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
      default:
        return 'Search for names in African records, family trees, cemeteries, and oral histories.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Search records'),
        foregroundColor: Colors.white,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      extendBodyBehindAppBar: true,
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            RecordsLibraryHero(
              asset: _heroAsset(),
              title: _heroTitle(),
              subtitle: _heroSubtitle(),
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
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
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
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      );
    } else {
      for (final m in _globalMatches) {
        out.add(
          _GlobalCard(
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
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      );
    } else {
      for (final m in _globalRecordMatches) {
        out.add(
          _GlobalRecordCard(
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
          _ResultCard(
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
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
    final TextTheme text = Theme.of(context).textTheme;
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
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.primary, size: 20),
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
                  color: AppColors.surfaceMuted,
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

/// A privacy-safe match from another member's tree. No deep-link (the user
/// isn't a member); instead offers to join that tree.
class _GlobalCard extends StatelessWidget {
  const _GlobalCard({
    required this.match,
    required this.joining,
    required this.onJoin,
  });

  final GlobalPersonMatch match;
  final bool joining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.travel_explore,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(match.fullName, style: text.titleMedium),
                  if (match.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(match.subtitle, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: joining ? null : onJoin,
              child: joining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join tree'),
            ),
          ],
        ),
      ),
    );
  }
}

/// An unattached record anybody has uploaded — no owning tree to deep-link
/// into (see search_records_global's privacy-safe projection), so this only
/// offers to view the file and/or copy it into the searcher's own records.
class _GlobalRecordCard extends StatelessWidget {
  const _GlobalRecordCard({
    required this.match,
    required this.saved,
    required this.onSave,
    required this.onOpen,
  });

  final GlobalRecordMatch match;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    match.type.icon,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(match.displayTitle, style: text.titleMedium),
                      if (match.subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(match.subtitle, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Spacer(),
                if (onOpen != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View'),
                  ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: saved ? null : onSave,
                  icon: Icon(saved ? Icons.check : Icons.add, size: 16),
                  label: Text(saved ? 'Saved' : 'Save to my records'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.hit,
    required this.saved,
    required this.onSave,
    required this.onOpen,
  });

  final HistoricalRecord hit;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    hit.type.icon,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(hit.name, style: text.titleMedium),
                      if (hit.subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(hit.subtitle, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                if ((hit.source ?? '').isNotEmpty) _SourceBadge(hit.source!),
                const Spacer(),
                if (onOpen != null)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View'),
                  ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: saved ? null : onSave,
                  icon: Icon(saved ? Icons.check : Icons.add, size: 16),
                  label: Text(saved ? 'Saved' : 'Save to tree'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small pill showing which provider a result came from.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge(this.source);
  final String source;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.public, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(source, style: text.labelSmall),
        ],
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
          Icon(icon, size: 44, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center, style: text.bodyMedium),
        ],
      ),
    );
  }
}

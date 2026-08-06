import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/gestures.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../profile/presentation/providers/family_tree_provider.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../widgets/global_person_card.dart';
import '../widgets/global_record_card.dart';
import '../widgets/historical_result_card.dart';
import '../widgets/record_card.dart';
import '../widgets/record_upload_sheet.dart';
import '../widgets/records_library_hero.dart';
import '../../domain/entities/global_person_match.dart';
import '../../domain/entities/global_record_match.dart';
import '../../domain/entities/historical_record.dart';
import '../../domain/entities/record.dart';
import '../providers/record_providers.dart';

/// Records library (brief §Phase 3): searchable, type-filterable list of source
/// documents with an upload entry point. Matches the "Records library" mockup.
class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  final Set<String> _savedCommunityIds = <String>{};
  final Set<String> _savedExternalIds = <String>{};
  final Set<String> _joiningTreeIds = <String>{};

  Future<void> _saveCommunityRecord(GlobalRecordMatch match) async {
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
      setState(() => _savedCommunityIds.add(match.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${match.displayTitle}" to your records.'),
        ),
      );
    }
  }

  Future<void> _saveExternalRecord(HistoricalRecord hit) async {
    final String treeId = ref.read(activeTreeIdProvider);
    final Record record = Record(
      id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
      treeId: treeId,
      type: hit.type,
      title: hit.name,
      repository: hit.collection ?? 'FamilySearch',
      date: _parseYear(hit.eventDate),
      notes: hit.subtitle,
      citationOverride: hit.sourceUrl,
      createdAt: DateTime.now(),
    );
    await ref.read(recordRepositoryProvider).upsertRecord(record);
    if (mounted) {
      setState(() => _savedExternalIds.add(hit.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved "${hit.name}" to your records.')));
    }
  }

  DateTime? _parseYear(String? eventDate) {
    if (eventDate == null) return null;
    final int? year = int.tryParse(eventDate.trim());
    if (year == null) return null;
    return DateTime(year);
  }

  Future<void> _joinTree(GlobalPersonMatch match) async {
    setState(() => _joiningTreeIds.add(match.treeId));
    try {
      await ref.read(familyTreeControllerProvider.notifier).joinTree(match.treeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined "${match.treeName ?? 'tree'}".')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join that tree.')),
        );
      }
    } finally {
      if (mounted) setState(() => _joiningTreeIds.remove(match.treeId));
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Record>> recordsAsync = ref.watch(recordsProvider);
    final List<Record> filtered = ref.watch(filteredRecordsProvider);
    final bool seesAllRecords = ref.watch(canSeeAllRecordsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        title: const Text('Records'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Upload record',
            color: Colors.white,
            onPressed: () => showRecordUploadSheet(
              context,
              ref,
              initialType: ref.read(recordTypeFilterProvider),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: <Widget>[
          RecordsLibraryHero(
            assets: const <String>[
              'assets/images/records_library_hero.jpg',
              'assets/images/records_library_hero_2.jpg',
              'assets/images/records_library_hero_3.jpg',
            ],
            title: seesAllRecords ? 'All records' : 'Your records',
            subtitle: seesAllRecords
                ? 'Every record uploaded across Rootsphere — birth certificates, marriage registrations, census records, and more.'
                : 'Birth certificates, marriage registrations, census records, and other official documents — all in one place.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: Theme.of(context).dividerColor),
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
                  const _SearchField(),
                  const SizedBox(height: AppSpacing.md),
                  const _TypeFilterChips(),
                ],
              ),
            ),
          ),
          Expanded(
            child: recordsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message(
                icon: Icons.error_outline,
                title: 'Could not load records',
                subtitle: '$e',
              ),
              data: (_) {
                final String query = ref.watch(recordSearchProvider).trim();
                // Records only surface once you actually search — matches
                // the per-category search screens, and keeps this "All
                // records" list from just dumping every upload by default.
                if (query.isEmpty) {
                  return const _Message(
                    icon: Icons.search,
                    title: 'Search to see records',
                    subtitle: 'Type a name, place, or title above.',
                  );
                }

                // Reaches everywhere the per-category search screens do, not
                // just records visible to this account: community
                // (cross-tree, unattached) records, cross-tree people, and
                // the external (FamilySearch-style) provider.
                final AsyncValue<List<GlobalRecordMatch>> communityAsync = ref
                    .watch(communityRecordSearchProvider(query));
                final List<GlobalRecordMatch> community =
                    communityAsync.value ?? const <GlobalRecordMatch>[];
                final bool communityLoading = communityAsync.isLoading;

                final AsyncValue<List<GlobalPersonMatch>> peopleAsync = ref
                    .watch(communityPeopleSearchProvider(query));
                final List<GlobalPersonMatch> people =
                    peopleAsync.value ?? const <GlobalPersonMatch>[];
                final bool peopleLoading = peopleAsync.isLoading;

                final AsyncValue<RecordSearchResult> externalAsync = ref
                    .watch(externalRecordSearchProvider(query));
                final RecordSearchResult? externalResult =
                    externalAsync.value;
                final List<HistoricalRecord> external =
                    externalResult?.records ?? const <HistoricalRecord>[];
                final bool externalLoading = externalAsync.isLoading;

                if (filtered.isEmpty &&
                    community.isEmpty &&
                    people.isEmpty &&
                    external.isEmpty &&
                    !communityLoading &&
                    !peopleLoading &&
                    !externalLoading) {
                  return _EmptyState(
                    isFiltering: true,
                    seesAllRecords: seesAllRecords,
                  );
                }

                final TextTheme text = Theme.of(context).textTheme;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    for (final r in filtered)
                      RecordCard(
                        record: r,
                        onTap: () =>
                            context.push('${AppRoutes.record}/${r.id}'),
                      ),
                    if (community.isNotEmpty || communityLoading) ...<Widget>[
                      if (filtered.isNotEmpty)
                        const SizedBox(height: AppSpacing.md),
                      Text('COMMUNITY RECORDS', style: text.labelSmall),
                      const SizedBox(height: AppSpacing.sm),
                      if (communityLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        for (final m in community)
                          GlobalRecordCard(
                            match: m,
                            saved: _savedCommunityIds.contains(m.id),
                            onSave: () => _saveCommunityRecord(m),
                            onOpen: m.fileUrl == null
                                ? null
                                : () => _open(m.fileUrl!),
                          ),
                    ],
                    if (people.isNotEmpty || peopleLoading) ...<Widget>[
                      if (filtered.isNotEmpty ||
                          community.isNotEmpty ||
                          communityLoading)
                        const SizedBox(height: AppSpacing.md),
                      Text('ACROSS ALL TREES', style: text.labelSmall),
                      const SizedBox(height: AppSpacing.sm),
                      if (peopleLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        for (final m in people)
                          GlobalPersonCard(
                            match: m,
                            joining: _joiningTreeIds.contains(m.treeId),
                            onJoin: () => _joinTree(m),
                          ),
                    ],
                    if (external.isNotEmpty || externalLoading) ...<Widget>[
                      if (filtered.isNotEmpty ||
                          community.isNotEmpty ||
                          communityLoading ||
                          people.isNotEmpty ||
                          peopleLoading)
                        const SizedBox(height: AppSpacing.md),
                      Text('HISTORICAL RECORDS', style: text.labelSmall),
                      const SizedBox(height: AppSpacing.sm),
                      if (externalLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (externalResult?.available == false)
                        Text(
                          externalResult?.message ??
                              'Historical record search is unavailable.',
                          style: text.bodyMedium,
                        )
                      else
                        for (final hit in external)
                          HistoricalResultCard(
                            hit: hit,
                            saved: _savedExternalIds.contains(hit.id),
                            onSave: () => _saveExternalRecord(hit),
                            onOpen: hit.sourceUrl == null
                                ? null
                                : () => _open(hit.sourceUrl!),
                          ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(recordSearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(recordSearchProvider.notifier).state = v,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search records…',
        prefixIcon: Icon(
          Icons.search,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  ref.read(recordSearchProvider.notifier).state = '';
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// Allows the chip row to be dragged with a mouse on desktop/web, not only
/// with touch gestures.
class _HorizontalScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class _TypeFilterChips extends ConsumerWidget {
  const _TypeFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "All" shows the saved records library. Tapping a specific type opens the
    // FamilySearch-style historical-records search scoped to that type.
    return SizedBox(
      height: 38,
      child: ScrollConfiguration(
        behavior: _HorizontalScrollBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: <Widget>[
              _Chip(
                label: 'All',
                selected: true,
                onSelected: () =>
                    context.push('${AppRoutes.records}/search/all'),
              ),
              for (final RecordType t in RecordType.values)
                if (t == RecordType.other)
                  const _OtherChip()
                else if (!_OtherChip.hiddenTypes.contains(t))
                  _Chip(
                    label: t.label,
                    selected: false,
                    onSelected: () =>
                        context.push('${AppRoutes.records}/search/${t.name}'),
                  ),
              const SizedBox(width: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherChip extends StatelessWidget {
  const _OtherChip();

  /// Types that are surfaced only through this "Other" menu, not as top-level
  /// chips on the Records screen.
  static const Set<RecordType> hiddenTypes = <RecordType>{
    RecordType.community,
    RecordType.cemetery,
    RecordType.school,
    RecordType.exam,
    RecordType.church,
    RecordType.transportManifest,
    RecordType.library,
    RecordType.museum,
    RecordType.archive,
    RecordType.landDocument,
    RecordType.will,
    RecordType.cooperativeAssociation,
    RecordType.politicalPartyRegister,
    RecordType.okadaUnion,
    RecordType.marketAssociation,
    RecordType.hospital,
    RecordType.flightManifest,
    RecordType.recruitmentAgency,
  };

  static const List<({RecordType type, String label})> _options =
      <({RecordType type, String label})>[
        (type: RecordType.community, label: 'Community records'),
        (type: RecordType.cemetery, label: 'Cemeteries'),
        (type: RecordType.school, label: 'Schools'),
        (type: RecordType.exam, label: 'Exams'),
        (type: RecordType.church, label: 'Church records'),
        (type: RecordType.transportManifest, label: 'Transportation manifests'),
        (type: RecordType.library, label: 'Libraries'),
        (type: RecordType.museum, label: 'Museums'),
        (type: RecordType.archive, label: 'Archives'),
        (type: RecordType.landDocument, label: 'Land documents'),
        (type: RecordType.will, label: 'Wills'),
        (
          type: RecordType.cooperativeAssociation,
          label: 'Cooperative associations',
        ),
        (
          type: RecordType.politicalPartyRegister,
          label: 'Political party registers',
        ),
        (type: RecordType.okadaUnion, label: 'Okada union'),
        (type: RecordType.marketAssociation, label: 'Market associations'),
        (type: RecordType.hospital, label: 'Hospitals'),
        (type: RecordType.flightManifest, label: 'Flight manifests'),
        (type: RecordType.recruitmentAgency, label: 'Recruitment agencies'),
      ];

  void _openMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      // `isScrollControlled` lifts the usual ~55%-of-screen cap so the sheet
      // can grow with the (now long) options list, but without an explicit
      // max it grows unbounded — tall enough to push the drag handle and
      // title off the top of the screen, with no way to reach them to
      // dismiss. Cap it so the inner ListView scrolls instead.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
      ),
      builder: (_) => _OtherOptionsSheet(options: _options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color textColor = theme.textTheme.bodyLarge!.color!;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: GestureDetector(
        onTap: () => _openMenu(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                RecordType.other.label,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_drop_down, size: 18, color: textColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherOptionsSheet extends StatelessWidget {
  const _OtherOptionsSheet({required this.options});

  final List<({RecordType type, String label})> options;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              'Other record types',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: options.length,
              itemBuilder: (_, int i) {
                final option = options[i];
                return ListTile(
                  title: Text(option.label, style: theme.textTheme.bodyLarge),
                  leading: Icon(
                    option.type.icon,
                    color: theme.colorScheme.primary,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(
                      '${AppRoutes.records}/search/${option.type.name}',
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected
              ? AppColors.onPrimary
              : theme.textTheme.bodyLarge!.color,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.surface,
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.dividerColor,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isFiltering, required this.seesAllRecords});

  /// True when a search query or type filter is active (so no results is a
  /// filtering outcome rather than an empty library).
  final bool isFiltering;

  /// True for admins/approved Finders/Indexers browsing everyone's records —
  /// "tap upload to add your first document" doesn't fit that view.
  final bool seesAllRecords;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: isFiltering ? Icons.search_off : Icons.folder_open_outlined,
      title: isFiltering ? 'No matching records' : 'No records yet',
      subtitle: isFiltering
          ? 'Try a different search or filter.'
          : seesAllRecords
          ? 'No records have been uploaded across Rootsphere yet.'
          : 'Tap the upload button to add your first document.',
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 48,
              color: AppColors.sunGold.withValues(alpha: 0.8),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: text.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, textAlign: TextAlign.center, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

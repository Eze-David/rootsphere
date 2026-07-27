import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter/gestures.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/record_card.dart';
import '../widgets/record_upload_sheet.dart';
import '../widgets/records_library_hero.dart';
import '../../domain/entities/record.dart';
import '../providers/record_providers.dart';

/// Records library (brief §Phase 3): searchable, type-filterable list of source
/// documents with an upload entry point. Matches the "Records library" mockup.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Record>> recordsAsync = ref.watch(recordsProvider);
    final List<Record> filtered = ref.watch(filteredRecordsProvider);
    final bool seesAllRecords = ref.watch(canSeeAllRecordsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
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
            onPressed: () => showRecordUploadSheet(context, ref),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: <Widget>[
          RecordsLibraryHero(
            assets: const <String>[
              'assets/images/records_library_hero.png',
              'assets/images/records_library_hero_2.png',
              'assets/images/records_library_hero_3.png',
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
                if (filtered.isEmpty) {
                  final bool isFiltering =
                      ref.watch(recordSearchProvider).trim().isNotEmpty ||
                      ref.watch(recordTypeFilterProvider) != null;
                  return _EmptyState(
                    isFiltering: isFiltering,
                    seesAllRecords: seesAllRecords,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final Record r = filtered[i];
                    return RecordCard(
                      record: r,
                      onTap: () => context.push('${AppRoutes.record}/${r.id}'),
                    );
                  },
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
        prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
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
      backgroundColor: AppColors.background,
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
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: GestureDetector(
        onTap: () => _openMenu(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cream,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                RecordType.other.label,
                style: const TextStyle(
                  color: AppColors.heroText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: AppColors.heroText,
              ),
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
              color: AppColors.border,
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.heroText,
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
                  title: Text(
                    option.label,
                    style: TextStyle(color: AppColors.heroText),
                  ),
                  leading: Icon(option.type.icon, color: AppColors.primary),
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
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected ? AppColors.onPrimary : AppColors.heroText,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.cream,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
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
            Text(
              title,
              style: text.titleMedium?.copyWith(color: AppColors.heroText),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, textAlign: TextAlign.center, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/african_locations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../archive/domain/entities/archive_record.dart';
import '../../../archive/presentation/providers/archive_providers.dart';
import '../../../archive/presentation/widgets/archive_record_detail_sheet.dart';
import '../../domain/entities/record.dart';

/// The public "browse the archive" experience: search + type/location
/// filters above a Records / Catalogues / Digital films tab set, showing
/// published Digital Records Repository entries. Reachable from the
/// Records screen's "Catalogue" mode toggle.
class CatalogueBrowser extends StatelessWidget {
  const CatalogueBrowser({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: <Widget>[
          const _CatalogueFilters(),
          TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).colorScheme.primary,
            tabs: const <Widget>[
              Tab(text: 'Records'),
              Tab(text: 'Catalogues'),
              Tab(text: 'Digital films'),
              Tab(text: 'Saved'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: <Widget>[
                _CatalogueRecordsList(),
                _CatalogueCollectionsList(),
                _CatalogueFilmsList(),
                _CatalogueSavedList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogueFilters extends ConsumerStatefulWidget {
  const _CatalogueFilters();

  @override
  ConsumerState<_CatalogueFilters> createState() => _CatalogueFiltersState();
}

class _CatalogueFiltersState extends ConsumerState<_CatalogueFilters> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(catalogueSearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RecordType? type = ref.watch(catalogueTypeFilterProvider);
    final String? country = ref.watch(catalogueCountryFilterProvider);
    final String? state = ref.watch(catalogueStateFilterProvider);
    final List<String> states = country == null
        ? const <String>[]
        : (africanStatesProvinces[country] ?? const <String>[]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _controller,
            onChanged: (v) => ref.read(catalogueSearchProvider.notifier).state = v,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Name, place, collection or keyword',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        ref.read(catalogueSearchProvider.notifier).state = '';
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<RecordType?>(
            initialValue: type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Record type'),
            items: <DropdownMenuItem<RecordType?>>[
              const DropdownMenuItem<RecordType?>(
                value: null,
                child: Text('All record types'),
              ),
              for (final RecordType t in RecordType.values)
                DropdownMenuItem<RecordType?>(
                  value: t,
                  child: Text(t.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (t) =>
                ref.read(catalogueTypeFilterProvider.notifier).state = t,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              // Same curated African country/state dataset the Records
              // search screen uses (core/data/african_locations.dart) —
              // not derived from whatever free text admins typed, which
              // produced duplicate near-matches ("Nigeria"/"nigeria").
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: country,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Country'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All countries'),
                    ),
                    for (final String c in africanCountries)
                      DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ],
                  onChanged: (c) {
                    ref.read(catalogueCountryFilterProvider.notifier).state = c;
                    // A state/region from the previous country would no
                    // longer be valid (or meaningful) for the new one.
                    ref.read(catalogueStateFilterProvider.notifier).state = null;
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: state,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'State / region',
                    hintText: country == null ? 'Select a country first' : null,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All locations'),
                    ),
                    for (final String s in states)
                      DropdownMenuItem<String?>(value: s, child: Text(s)),
                  ],
                  onChanged: country == null
                      ? null
                      : (s) => ref.read(catalogueStateFilterProvider.notifier).state = s,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogueRecordsList extends ConsumerWidget {
  const _CatalogueRecordsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ArchiveRecord> records = ref.watch(filteredCatalogueRecordsProvider);
    if (records.isEmpty) {
      return const _CatalogueEmptyState();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _CatalogueRecordCard(record: records[index]),
    );
  }
}

class _CatalogueFilmsList extends ConsumerWidget {
  const _CatalogueFilmsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ArchiveRecord> records = ref.watch(filteredCatalogueFilmsProvider);
    if (records.isEmpty) {
      return const _CatalogueEmptyState(
        message: 'No digital films or recordings match your search.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _CatalogueRecordCard(record: records[index]),
    );
  }
}

class _CatalogueSavedList extends ConsumerWidget {
  const _CatalogueSavedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ArchiveRecord> records = ref.watch(filteredSavedArchiveRecordsProvider);
    if (records.isEmpty) {
      return const _CatalogueEmptyState(
        message: 'Nothing saved yet — tap "Save collection" on a record to keep it here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _CatalogueRecordCard(record: records[index]),
    );
  }
}

class _CatalogueCollectionsList extends ConsumerWidget {
  const _CatalogueCollectionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ArchiveRecord> records = ref.watch(filteredCatalogueRecordsProvider);
    if (records.isEmpty) {
      return const _CatalogueEmptyState();
    }

    final Map<String, List<ArchiveRecord>> byCollection = <String, List<ArchiveRecord>>{};
    for (final ArchiveRecord r in records) {
      final String key = r.collection.trim().isEmpty ? 'Uncategorized' : r.collection.trim();
      byCollection.putIfAbsent(key, () => <ArchiveRecord>[]).add(r);
    }
    final List<String> names = byCollection.keys.toList()..sort();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: names.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final String name = names[index];
        final List<ArchiveRecord> group = byCollection[name]!;
        return _CollectionCard(
          name: name,
          records: group,
          onTap: () {
            ref.read(catalogueSearchProvider.notifier).state = name;
            DefaultTabController.of(context).animateTo(0); // Records
          },
        );
      },
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.name,
    required this.records,
    required this.onTap,
  });

  final String name;
  final List<ArchiveRecord> records;
  final VoidCallback onTap;

  ArchiveAccessStatus get _bestAccess {
    if (records.any((r) => r.accessStatus == ArchiveAccessStatus.online)) {
      return ArchiveAccessStatus.online;
    }
    if (records.any((r) => r.accessStatus == ArchiveAccessStatus.permission)) {
      return ArchiveAccessStatus.permission;
    }
    return ArchiveAccessStatus.archive;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int fileCount = records.fold(0, (sum, r) => sum + r.files.length);
    final Set<String> locations = <String>{
      for (final r in records)
        if (r.stateRegion.isNotEmpty) r.stateRegion,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (locations.isNotEmpty) locations.join(', '),
                      '${records.length} record${records.length == 1 ? '' : 's'}',
                      '$fileCount file${fileCount == 1 ? '' : 's'}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            _AccessBadge(status: _bestAccess),
          ],
        ),
      ),
    );
  }
}

class _CatalogueRecordCard extends ConsumerWidget {
  const _CatalogueRecordCard({required this.record});
  final ArchiveRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> meta = <String>[
      if (record.collection.isNotEmpty) record.collection,
      if (record.stateRegion.isNotEmpty) record.stateRegion,
      if (record.dateRangeLabel.isNotEmpty) record.dateRangeLabel,
    ];

    return InkWell(
      onTap: () => showArchiveRecordDetail(context, ref, record),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.displayTitle,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      meta.join(' · '),
                      style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _AccessBadge(status: record.accessStatus),
          ],
        ),
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.status});
  final ArchiveAccessStatus status;

  Color _color() {
    switch (status) {
      case ArchiveAccessStatus.online:
        return AppColors.success;
      case ArchiveAccessStatus.permission:
        return AppColors.sunGold;
      case ArchiveAccessStatus.archive:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        status.label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CatalogueEmptyState extends StatelessWidget {
  const _CatalogueEmptyState({
    this.message = 'No published records match your search yet.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    // A ScrollView (not just Center) — when the filter fields above push
    // this tab's available height down to only a few dozen pixels (small
    // screens, or the state/region row visible), the fixed icon+text
    // content can be taller than what's left; scrolling avoids a hard
    // RenderFlex overflow instead of trying to shrink content that's
    // already fairly minimal.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.local_library_outlined,
            size: 40,
            color: AppColors.sunGold.withValues(alpha: 0.8),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

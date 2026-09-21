import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../providers/record_providers.dart';
import '../widgets/catalogue_browser.dart';
import '../widgets/record_upload_sheet.dart';
import '../widgets/records_library_hero.dart';
import 'historical_records_search_screen.dart';

/// Records tab: a "Records" mode (the structured African-ancestors search,
/// embedded directly — see HistoricalRecordsSearchScreen(embedded: true))
/// and a "Catalogue" mode (the admin-curated Digital Records Repository,
/// see CatalogueBrowser).
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool seesAllRecords = ref.watch(canSeeAllRecordsProvider);
    final RecordsViewMode mode = ref.watch(recordsViewModeProvider);

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              'assets/images/rootsphere-logo-espresso-v6-cropped.png',
              width: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: AppSpacing.xs),
            const Text('RootSphere Records'),
          ],
        ),
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
              'assets/images/records_library_hero.jpg',
              'assets/images/records_library_hero_2.jpg',
              'assets/images/records_library_hero_3.jpg',
            ],
            title: seesAllRecords ? 'All records' : 'Your records',
            subtitle: seesAllRecords
                ? 'Every record uploaded across Rootsphere — birth certificates, marriage registrations, census records, and more.'
                : 'Birth certificates, marriage registrations, census records, and other official documents — all in one place.',
          ),
          const _RecordsModeToggle(),
          Expanded(
            child: mode == RecordsViewMode.catalogue
                ? const CatalogueBrowser()
                : HistoricalRecordsSearchScreen(
                    embedded: true,
                    initialQuery: ref.watch(recordSearchProvider),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecordsModeToggle extends ConsumerWidget {
  const _RecordsModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecordsViewMode mode = ref.watch(recordsViewModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: SegmentedButton<RecordsViewMode>(
        segments: const <ButtonSegment<RecordsViewMode>>[
          ButtonSegment<RecordsViewMode>(
            value: RecordsViewMode.mine,
            label: Text('Records'),
            icon: Icon(Icons.folder_outlined),
          ),
          ButtonSegment<RecordsViewMode>(
            value: RecordsViewMode.catalogue,
            label: Text('Catalogue'),
            icon: Icon(Icons.local_library_outlined),
          ),
        ],
        selected: <RecordsViewMode>{mode},
        onSelectionChanged: (selection) =>
            ref.read(recordsViewModeProvider.notifier).state = selection.first,
      ),
    );
  }
}

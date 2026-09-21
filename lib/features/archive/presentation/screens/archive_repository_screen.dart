import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../collab/presentation/providers/role_verification_providers.dart';
import '../widgets/add_archive_record_tab.dart';
import '../widgets/archive_access_requests_tab.dart';
import '../widgets/archive_review_queue_tab.dart';
import '../widgets/stored_collections_tab.dart';

/// Admin-only "RootSphere Digital Records Repository": a curated catalogue
/// of digitized civil/historical records, separate from the per-tree
/// `records` feature. Reachable only if [isPlatformAdminProvider] is true —
/// RLS blocks the underlying `archive_records` table/bucket for anyone else
/// regardless, this is just the UI gate (same convention as the other
/// `/admin/*` screens).
class ArchiveRepositoryScreen extends ConsumerWidget {
  const ArchiveRepositoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;

    if (!isAdmin) {
      return const Scaffold(
        body: Center(child: Text('This page is for admins only.')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Digital records repository'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Add record'),
              Tab(text: 'Review queue'),
              Tab(text: 'Stored collections'),
              Tab(text: 'Access requests'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            AddArchiveRecordTab(),
            ArchiveReviewQueueTab(),
            StoredCollectionsTab(),
            ArchiveAccessRequestsTab(),
          ],
        ),
      ),
    );
  }
}

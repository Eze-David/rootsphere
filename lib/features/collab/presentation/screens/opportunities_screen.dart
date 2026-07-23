import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../tree/data/services/geocoding_service.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../../tree/presentation/widgets/osm_attribution.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/opportunity.dart';
import '../providers/donation_providers.dart';
import '../providers/opportunity_providers.dart';
import '../widgets/add_opportunity_sheet.dart';
import '../widgets/donate_dialog.dart';
import '../widgets/opportunity_actions.dart';
import '../widgets/opportunity_card.dart';
import 'claim_workspace_screen.dart';
import 'my_opportunities_screen.dart';

/// The Phase 5 collaboration board: a list of open record-gathering
/// opportunities that community members can claim, work on, and verify.
class OpportunitiesScreen extends ConsumerStatefulWidget {
  const OpportunitiesScreen({super.key, this.openOpportunityId});

  /// When set (e.g. arriving from a notification tap), the matching
  /// opportunity's detail sheet is opened automatically once it loads,
  /// rather than leaving the user to find it on the board themselves.
  final String? openOpportunityId;

  @override
  ConsumerState<OpportunitiesScreen> createState() =>
      _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends ConsumerState<OpportunitiesScreen> {
  String? _pendingOpenId;

  @override
  void initState() {
    super.initState();
    _pendingOpenId = widget.openOpportunityId;
  }

  @override
  void didUpdateWidget(covariant OpportunitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openOpportunityId != null &&
        widget.openOpportunityId != oldWidget.openOpportunityId) {
      _pendingOpenId = widget.openOpportunityId;
    }
  }

  void _maybeAutoOpen(List<CollaborationOpportunity> opportunities) {
    final String? id = _pendingOpenId;
    if (id == null) return;
    final CollaborationOpportunity? match = opportunities
        .cast<CollaborationOpportunity?>()
        .firstWhere((o) => o?.id == id, orElse: () => null);
    if (match == null) return;
    _pendingOpenId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showOpportunityDetail(context, ref, match);
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final opportunities = ref.watch(filteredOpportunitiesProvider);
    final counts = ref.watch(opportunityCountsProvider);
    final filter = ref.watch(opportunityFilterProvider);
    final async = ref.watch(opportunitiesProvider);
    if (async.hasValue) _maybeAutoOpen(async.value!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunities'),
        actions: <Widget>[
          IconButton(
            tooltip: 'My opportunities',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MyOpportunitiesScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Map view',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _OpportunityMapScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add opportunity',
            icon: const Icon(Icons.add),
            onPressed: () => showAddOpportunitySheet(context),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'Record gathering board — claim a task and help the community.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<OpportunityStatus?>(
                segments: <ButtonSegment<OpportunityStatus?>>[
                  ButtonSegment<OpportunityStatus?>(
                    value: null,
                    label: Text(
                      'All (${counts.values.reduce((a, b) => a + b)})',
                    ),
                  ),
                  ButtonSegment<OpportunityStatus?>(
                    value: OpportunityStatus.open,
                    label: Text('Open (${counts[OpportunityStatus.open]})'),
                  ),
                  ButtonSegment<OpportunityStatus?>(
                    value: OpportunityStatus.claimed,
                    label: Text(
                      'Claimed (${counts[OpportunityStatus.claimed]})',
                    ),
                  ),
                  ButtonSegment<OpportunityStatus?>(
                    value: OpportunityStatus.verified,
                    label: Text(
                      'Verified (${counts[OpportunityStatus.verified]})',
                    ),
                  ),
                ],
                selected: <OpportunityStatus?>{filter},
                onSelectionChanged: (selected) {
                  ref.read(opportunityFilterProvider.notifier).state =
                      selected.first;
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _ContributionHeader(currentUserId: _currentUserId),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: async.isLoading
                ? const Center(child: CircularProgressIndicator())
                : async.hasError
                ? Center(
                    child: Text(
                      'Could not load opportunities.',
                      style: text.bodyMedium?.copyWith(color: AppColors.error),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: opportunities.length,
                    itemBuilder: (_, index) {
                      final opportunity = opportunities[index];
                      return OpportunityCard(
                        opportunity: opportunity,
                        currentUserId: _currentUserId,
                        onTap: () =>
                            showOpportunityDetail(context, ref, opportunity),
                        onClaim: () =>
                            claimOpportunity(context, ref, opportunity),
                        onContinueWork: () =>
                            openClaimWorkspace(context, opportunity),
                        onSubmitResult: () =>
                            submitOpportunityResult(context, ref, opportunity),
                        onVerify: () =>
                            verifyOpportunityResult(context, ref, opportunity),
                        onUnclaim: () =>
                            unclaimOpportunity(context, ref, opportunity),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String get _currentUserId {
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  }
}

class _ContributionHeader extends ConsumerWidget {
  const _ContributionHeader({required this.currentUserId});
  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final my = ref.watch(myContributionProvider);
    if (my == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Your contributions', style: text.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${my.verifiedCount} verified · ${my.claimedCount} claimed',
                  style: text.bodyMedium,
                ),
                Text(
                  '${my.reputation} reputation',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (my.badges.isNotEmpty)
            Row(
              children: my.badges.take(3).map((badge) {
                return Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Tooltip(
                    message: '${badge.label}: ${badge.description}',
                    child: Icon(badge.icon, color: AppColors.primary, size: 22),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

/// Plots every opportunity that has a location on a real map: opportunities
/// with explicit [CollaborationOpportunity.latitude]/[longitude] use those
/// directly; others are geocoded from their free-text [CollaborationOpportunity.location]
/// (same cached `geocode` Edge Function as the family tree's location map).
/// Opportunities sharing a location are grouped under one pin.
class _OpportunityMapScreen extends ConsumerWidget {
  const _OpportunityMapScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final async = ref.watch(opportunitiesProvider);
    final List<CollaborationOpportunity> opportunities =
        async.value ?? const <CollaborationOpportunity>[];

    final Map<String, List<CollaborationOpportunity>> byKey =
        <String, List<CollaborationOpportunity>>{};
    for (final o in opportunities) {
      if (o.hasGeo) {
        byKey
            .putIfAbsent(
              'geo:${o.latitude}:${o.longitude}',
              () => <CollaborationOpportunity>[],
            )
            .add(o);
      } else if ((o.location ?? '').trim().isNotEmpty) {
        byKey
            .putIfAbsent(
              'loc:${o.location!.trim().toLowerCase()}',
              () => <CollaborationOpportunity>[],
            )
            .add(o);
      }
    }

    final List<_OppGroup> groups = <_OppGroup>[];
    for (final entry in byKey.entries) {
      final List<CollaborationOpportunity> list = entry.value;
      final CollaborationOpportunity first = list.first;
      LatLng? point;
      if (first.hasGeo) {
        point = LatLng(first.latitude!, first.longitude!);
      } else {
        final GeocodeResult? result = ref
            .watch(geocodeProvider(first.location!.trim()))
            .value;
        if (result != null) point = LatLng(result.lat, result.lon);
      }
      if (point == null) continue;
      groups.add(_OppGroup(opportunities: list, point: point));
    }

    final int plotted = groups.fold<int>(
      0,
      (n, g) => n + g.opportunities.length,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Map of opportunities')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              groups.isEmpty
                  ? 'No opportunities have a location yet.'
                  : '$plotted opportunit${plotted == 1 ? 'y' : 'ies'} plotted.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.map_outlined,
                          size: 64,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Geo-tagged opportunity map',
                          style: text.titleMedium,
                        ),
                      ],
                    ),
                  )
                // See TreeMapScreen for why this guard/config exists: a
                // genuine 0×0 or unbounded layout pass throws Infinity/NaN in
                // flutter_map's tile math, and the default tile fade-in
                // throws "setState() called during build" on cached tiles.
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final bool sizeReady =
                          constraints.maxWidth.isFinite &&
                          constraints.maxHeight.isFinite &&
                          constraints.maxWidth > 0 &&
                          constraints.maxHeight > 0;
                      if (!sizeReady) return const SizedBox.shrink();

                      final LatLng centre = groups.first.point;
                      final double zoom = groups.length > 1 ? 3 : 12;
                      return FlutterMap(
                        options: MapOptions(
                          initialCenter: centre,
                          initialZoom: zoom,
                          minZoom: 2,
                          maxZoom: 18,
                        ),
                        children: <Widget>[
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                            subdomains: const <String>['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.rootsphere.app',
                            tileDisplay: const TileDisplay.instantaneous(),
                          ),
                          MarkerLayer(
                            markers: <Marker>[
                              for (final g in groups)
                                Marker(
                                  point: g.point,
                                  width: 60,
                                  height: 44,
                                  alignment: Alignment.topCenter,
                                  child: _OppPin(
                                    group: g,
                                    onTap: () => _onPinTap(context, g),
                                  ),
                                ),
                            ],
                          ),
                          const OsmAttribution(),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _onPinTap(BuildContext context, _OppGroup g) {
    if (g.opportunities.length == 1) {
      _showOpportunitySheet(context, g.opportunities.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                g.opportunities.first.location ?? '',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final o in g.opportunities)
              ListTile(
                title: Text(o.title),
                subtitle: Text(o.status.label),
                onTap: () {
                  Navigator.pop(ctx);
                  _showOpportunitySheet(context, o);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showOpportunitySheet(BuildContext context, CollaborationOpportunity o) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                o.title,
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              StatusChip(
                status: o.status,
                changesRequested: o.changesRequested,
              ),
              if ((o.location ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      o.location!,
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
              if (o.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(o.description, style: Theme.of(ctx).textTheme.bodyLarge),
              ],
              const SizedBox(height: AppSpacing.md),
              Consumer(
                builder: (context, ref, _) {
                  final int raisedCents = ref.watch(
                    opportunityRaisedCentsProvider(o.id),
                  );
                  if (raisedCents == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.favorite,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '\$${(raisedCents / 100).toStringAsFixed(2)} raised to support this research',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Consumer(
                builder: (context, ref, _) => SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDonateDialog(context, ref, o);
                    },
                    icon: const Icon(Icons.favorite_border, size: 18),
                    label: const Text('Support this research'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ClaimWorkspaceScreen(opportunityId: o.id),
                      ),
                    );
                  },
                  child: const Text('Open opportunity'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OppGroup {
  _OppGroup({required this.opportunities, required this.point});
  final List<CollaborationOpportunity> opportunities;
  final LatLng point;
}

class _OppPin extends StatefulWidget {
  const _OppPin({required this.group, required this.onTap});
  final _OppGroup group;
  final VoidCallback onTap;

  @override
  State<_OppPin> createState() => _OppPinState();
}

class _OppPinState extends State<_OppPin> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Same hover treatment as the tree's cards/placeholder slots: swap to
    // sunGold on hover rather than introducing a new highlight colour.
    final Color pinColor = _hovered ? AppColors.sunGold : AppColors.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.group.opportunities.length > 1)
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: pinColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  '${widget.group.opportunities.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Icon(Icons.location_on, color: pinColor, size: _hovered ? 40 : 36),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../hints/domain/entities/hint.dart';
import '../../../hints/presentation/providers/hint_providers.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../records/domain/entities/record.dart';
import '../../../records/presentation/providers/record_providers.dart';
import '../../../tree/domain/entities/edit_history_entry.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../widgets/tree_progress_ring_painter.dart';
import '../widgets/what_to_watch_section.dart';

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Home dashboard: a branded hero + search card, a tree-completeness ring,
/// quick actions, a "family at a glance" preview, recent activity, and the
/// existing hints-driven sections below.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Person> people =
        ref.watch(personsProvider).value ?? const <Person>[];
    final AppUser? user = ref.watch(authStateProvider).value;
    final int unreadNotifications = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            _HeroSearchCard(user: user, unreadNotifications: unreadNotifications),
            const SizedBox(height: AppSpacing.lg),
            _TreeProgressCard(people: people),
            const SizedBox(height: AppSpacing.xl),
            const _QuickActionsGrid(),
            const SizedBox(height: AppSpacing.xl),
            const _FamilyAtAGlance(),
            const SizedBox(height: AppSpacing.xl),
            const _RecentActivity(),
            const SizedBox(height: AppSpacing.xl),
            const WhatToWatchSection(),
            const SizedBox(height: AppSpacing.xl),
            const _NearbyOpportunity(),
          ],
        ),
      ),
    );
  }
}

class _HeroSearchCard extends ConsumerStatefulWidget {
  const _HeroSearchCard({required this.user, required this.unreadNotifications});
  final AppUser? user;
  final int unreadNotifications;

  @override
  ConsumerState<_HeroSearchCard> createState() => _HeroSearchCardState();
}

class _HeroSearchCardState extends ConsumerState<_HeroSearchCard> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final String query = _controller.text.trim();
    if (query.isEmpty) return;
    // Reuses the Records screen's own unified search (person + record +
    // external results) rather than building a second search stack.
    ref.read(recordSearchProvider.notifier).state = query;
    ref.read(recordsViewModeProvider.notifier).state = RecordsViewMode.mine;
    context.go(AppRoutes.records);
  }

  String? _firstName(AppUser? user) {
    if (user == null) return null;
    final String? dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn.split(' ').first;
    final String email = user.email;
    if (email.isEmpty) return null;
    final String local = email.split('@').first;
    if (local.isEmpty) return null;
    return local[0].toUpperCase() + local.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int hour = DateTime.now().hour;
    final String part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final String? name = _firstName(widget.user);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        // Deliberately a fixed brand-dark card (not theme-swapped) — this is
        // the "espresso/forest" hero accent from the mockup, meant to stay
        // dark with light text in both app themes, unlike a plain surface.
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  'YOUR HISTORY LIVES HERE',
                  style: text.labelSmall?.copyWith(
                    color: AppColors.sunGold,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  IconButton(
                    onPressed: () => context.push(AppRoutes.notifications),
                    icon: const Icon(Icons.notifications_none, color: Colors.white),
                  ),
                  if (widget.unreadNotifications > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.sunGold,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          border: Border.all(color: AppColors.primary, width: 1.5),
                        ),
                        child: Text(
                          widget.unreadNotifications > 9 ? '9+' : '${widget.unreadNotifications}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name == null
                ? '$part. Continue building your family story.'
                : '$part, $name. Continue building your family story.',
            style: text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "Connect generations, preserve memories and keep the records that prove your family's journey.",
            style: text.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _search(),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Search a person, place or record',
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _search,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sunGold,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                ),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TreeProgressCard extends StatelessWidget {
  const _TreeProgressCard({required this.people});
  final List<Person> people;

  /// A heuristic, not a precise metric: the fraction of a few core fields
  /// filled in, averaged across every person in the tree. Deliberately
  /// simple (photo, birth date, birth place, at least one parent linked, at
  /// least one spouse linked) rather than a weighted/scientific score.
  double get _completeness {
    if (people.isEmpty) return 0;
    double sum = 0;
    for (final Person p in people) {
      int filled = 0;
      const int total = 5;
      if ((p.photoUrl ?? '').isNotEmpty) filled++;
      if (p.birthDate != null) filled++;
      if ((p.birthPlace ?? '').isNotEmpty) filled++;
      if (p.parentIds.isNotEmpty) filled++;
      if (p.spouseIds.isNotEmpty) filled++;
      sum += filled / total;
    }
    return sum / people.length;
  }

  /// Persons with neither a parent nor a spouse linked — disconnected nodes
  /// the "add N more relatives" nudge points at.
  int get _unconnectedCount =>
      people.where((p) => p.parentIds.isEmpty && p.spouseIds.isEmpty).length;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double percent = _completeness;
    final int pct = (percent * 100).round();
    final int unconnected = _unconnectedCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Your tree progress', style: text.titleMedium),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 140,
            height: 140,
            child: CustomPaint(
              painter: TreeProgressRingPainter(
                percent: percent,
                trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                progressColor: AppColors.sunGold,
              ),
              child: Center(
                child: Text(
                  '$pct%',
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${people.length} people connected',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (unconnected > 0) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              'Add $unconnected more relative${unconnected == 1 ? '' : 's'} to complete this branch',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('What would you like to do?', style: text.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                icon: Icons.account_tree_outlined,
                title: 'View Family Tree',
                subtitle: 'Explore ancestors and descendants',
                onTap: () => context.go(AppRoutes.tree),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.person_add_alt,
                title: 'Add a Relative',
                subtitle: 'Create a new family profile',
                // The tree screen owns person creation/editing — no
                // separate top-level "add relative" entry point exists.
                onTap: () => context.go(AppRoutes.tree),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                icon: Icons.search,
                title: 'Search Records',
                subtitle: 'Find historical evidence',
                onTap: () => context.go(AppRoutes.records),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.mic_none,
                title: 'Record a Story',
                subtitle: 'Preserve an oral history',
                // Voice notes are captured per-person on the tree — no
                // separate top-level recording flow exists yet.
                onTap: () => context.go(AppRoutes.tree),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, size: 20),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyAtAGlance extends ConsumerWidget {
  const _FamilyAtAGlance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? myId = ref.watch(myPersonIdForActiveTreeProvider).value;
    final Map<String, Person> byId = ref.watch(personMapProvider);
    final Person? me = myId == null ? null : byId[myId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('Your family at a glance', style: text.titleMedium)),
            if (me != null)
              TextButton(
                onPressed: () {
                  setFocusPerson(ref, me.id);
                  context.go(AppRoutes.tree);
                },
                child: const Text('Open full tree →'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: me == null ? const _MarkMeCta() : _FamilyRow(me: me, byId: byId),
        ),
      ],
    );
  }
}

class _MarkMeCta extends StatelessWidget {
  const _MarkMeCta();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        const Icon(Icons.person_pin_circle_outlined, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'Open your profile in the tree and choose "Mark as me" to see your family here.',
            style: text.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _FamilyRow extends StatelessWidget {
  const _FamilyRow({required this.me, required this.byId});
  final Person me;
  final Map<String, Person> byId;

  @override
  Widget build(BuildContext context) {
    Person? father;
    Person? mother;
    for (final String pid in me.parentIds) {
      final Person? p = byId[pid];
      if (p == null) continue;
      if (p.sex == Sex.male) father ??= p;
      if (p.sex == Sex.female) mother ??= p;
    }
    final Person? parent = father ?? mother;
    final String parentLabel = father != null ? 'Father' : 'Mother';

    Person? child;
    String childLabel = 'Child';
    for (final Person p in byId.values) {
      if (p.parentIds.contains(me.id)) {
        child = p;
        childLabel = p.sex == Sex.male
            ? 'Son'
            : p.sex == Sex.female
            ? 'Daughter'
            : 'Child';
        break;
      }
    }

    final List<Widget> nodes = <Widget>[
      if (parent != null) _FamilyNode(person: parent, label: parentLabel),
      _FamilyNode(person: me, label: 'You', highlight: true),
      if (child != null) _FamilyNode(person: child, label: childLabel),
    ];

    return Row(
      children: <Widget>[
        for (int i = 0; i < nodes.length; i++) ...<Widget>[
          if (i > 0)
            Expanded(
              child: Container(height: 1, color: Theme.of(context).dividerColor),
            ),
          nodes[i],
        ],
      ],
    );
  }
}

class _FamilyNode extends StatelessWidget {
  const _FamilyNode({
    required this.person,
    required this.label,
    this.highlight = false,
  });
  final Person person;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircleAvatar(
          radius: 24,
          backgroundColor: highlight ? AppColors.sunGold : AppColors.avatarGreen,
          child: Text(
            _initialsOf(person.fullName),
            style: text.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          person.fullName,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(label, style: text.bodySmall?.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<_Activity> items = _build(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('Recent activity', style: text.titleMedium)),
            TextButton(
              onPressed: () => context.push(AppRoutes.notifications),
              child: const Text('View all'),
            ),
          ],
        ),
        if (items.isEmpty)
          Text(
            'Nothing yet. Add people and records to get started.',
            style: text.bodyMedium,
          )
        else
          for (final a in items) _ActivityRow(activity: a),
      ],
    );
  }

  List<_Activity> _build(WidgetRef ref) {
    final List<_Activity> out = <_Activity>[];
    final Map<String, Person> byId = ref.watch(personMapProvider);

    // Highest-confidence pending hint — a suggestion rather than something
    // that happened, so it's capped to one rather than merged by recency.
    final List<Hint> hints = ref.watch(pendingHintsProvider);
    if (hints.isNotEmpty) {
      final Hint h = hints.first;
      final String who = byId[h.personId]?.fullName ?? h.type.label;
      out.add(
        _Activity(
          icon: Icons.lightbulb_outline,
          tint: AppColors.avatarAmber,
          title: 'Hint · $who',
          subtitle: h.title,
          timestamp: h.createdAt ?? DateTime.now(),
          onTap: (ctx) => ctx.push(AppRoutes.hints),
        ),
      );
    }

    // Records *this account* uploaded — recordsProvider can include records
    // across every tree for admins/approved Finders/Indexers (see
    // canSeeAllRecordsProvider), which isn't "your" recent activity.
    final String? uid = ref.watch(authStateProvider).value?.id;
    final List<Record> records = (ref.watch(recordsProvider).value ??
            const <Record>[])
        .where((r) => r.ownerId == uid)
        .toList();
    for (final r in records) {
      out.add(
        _Activity(
          icon: r.mediaKind == RecordMediaKind.image
              ? Icons.image_outlined
              : Icons.description_outlined,
          tint: AppColors.avatarBlue,
          title: r.displayTitle,
          subtitle: '${r.type.label} record',
          timestamp: r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          onTap: (ctx) => ctx.push('${AppRoutes.record}/${r.id}'),
        ),
      );
    }

    // People added or edited.
    final List<EditHistoryEntry> treeActivity =
        ref.watch(recentTreeActivityProvider).value ??
        const <EditHistoryEntry>[];
    for (final e in treeActivity) {
      final String name = byId[e.personId]?.fullName ?? 'Someone';
      final bool isCreation = e.changedFields.isEmpty;
      out.add(
        _Activity(
          icon: isCreation ? Icons.person_add_alt : Icons.edit_outlined,
          tint: AppColors.avatarGreen,
          title: isCreation ? 'Added · $name' : 'Edited · $name',
          subtitle: isCreation ? 'New person added to the tree' : e.reason,
          timestamp: e.createdAt,
          onTap: (ctx) => ctx.push('${AppRoutes.person}/${e.personId}'),
        ),
      );
    }

    // Merge everything by actual recency rather than fixed per-type slots.
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out.take(6).toList();
  }
}

class _Activity {
  const _Activity({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.onTap,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final void Function(BuildContext) onTap;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});
  final _Activity activity;

  /// "Just now" / "5m ago" / "3h ago" / "2d ago" / a short date beyond that —
  /// same convention as the notifications list.
  String get _relativeTime {
    final Duration diff = DateTime.now().difference(activity.timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final DateTime d = activity.timestamp;
    final String time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day}/${d.month}/${d.year} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => activity.onTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: activity.tint.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(activity.icon, size: 20, color: AppColors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    activity.title,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    activity.subtitle,
                    style: text.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _relativeTime,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Surfaces the highest-confidence record-match hint as a "nearby
/// opportunity"; hidden when there are none.
class _NearbyOpportunity extends ConsumerWidget {
  const _NearbyOpportunity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Hint> hints = ref.watch(pendingHintsProvider);
    final Hint? match = hints
        .where((h) => h.type == HintType.recordMatch)
        .cast<Hint?>()
        .firstWhere((_) => true, orElse: () => null);
    if (match == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('NEARBY OPPORTUNITY', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: () => context.push(AppRoutes.hints),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(match.title, style: text.titleMedium)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.statusOpen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Text(
                        'Open',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.statusOpen,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(match.description, style: text.bodyMedium),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      'Review →',
                      style: text.labelLarge?.copyWith(color: AppColors.link),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
import '../../../profile/presentation/providers/family_tree_provider.dart';
import '../../../records/domain/entities/record.dart';
import '../../../records/presentation/providers/record_providers.dart';
import '../../../tree/domain/entities/edit_history_entry.dart';
import '../../../tree/domain/entities/person.dart';
import '../../../tree/presentation/providers/tree_providers.dart';

/// Home dashboard (brief §Phase 4 mockup): greeting, key stats, recent activity
/// and a surfaced opportunity. The Hints stat and activity feed are the entry
/// points into the Hints & AI feature.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Person> people =
        ref.watch(personsProvider).value ?? const <Person>[];
    final List<Record> records =
        ref.watch(recordsProvider).value ?? const <Record>[];
    final int hintCount = ref.watch(pendingHintCountProvider);
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
            _Greeting(
              user: user,
              treeName: _treeName(ref),
              unreadNotifications: unreadNotifications,
            ),
            const SizedBox(height: AppSpacing.lg),
            _StatsRow(
              people: people.length,
              records: records.length,
              hints: hintCount,
            ),
            const SizedBox(height: AppSpacing.xl),
            const _RecentActivity(),
            const SizedBox(height: AppSpacing.xl),
            const _NearbyOpportunity(),
          ],
        ),
      ),
    );
  }

  String _treeName(WidgetRef ref) {
    final String activeId = ref.watch(activeTreeIdProvider);
    final trees = ref.watch(familyTreeControllerProvider).value;
    if (trees != null) {
      for (final t in trees) {
        if (t.id == activeId) return '${t.name} family tree';
      }
    }
    if (activeId == 'okonkwo') return 'Okonkwo family tree';
    return 'Your family tree';
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.user,
    required this.treeName,
    required this.unreadNotifications,
  });
  final AppUser? user;
  final String treeName;
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int hour = DateTime.now().hour;
    final String part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final String? name = _firstName(user);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name == null ? part : '$part, $name',
                style: text.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text(treeName, style: text.bodyMedium),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            IconButton.outlined(
              onPressed: () => context.push(AppRoutes.notifications),
              icon: const Icon(Icons.notifications_none),
            ),
            if (unreadNotifications > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.sunGold,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.background, width: 1.5),
                  ),
                  child: Text(
                    unreadNotifications > 9 ? '9+' : '$unreadNotifications',
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
    );
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
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.people,
    required this.records,
    required this.hints,
  });
  final int people;
  final int records;
  final int hints;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatCard(
            value: '$people',
            label: 'PEOPLE',
            onTap: () => _go(context, AppRoutes.tree),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            value: '$records',
            label: 'RECORDS',
            onTap: () => _go(context, AppRoutes.records),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            value: '$hints',
            label: 'HINTS',
            highlight: hints > 0,
            onTap: () => context.push(AppRoutes.hints),
          ),
        ),
      ],
    );
  }

  void _go(BuildContext context, String location) => context.go(location);
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });
  final String value;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: highlight ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          children: <Widget>[
            Text(value, style: text.displayMedium),
            const SizedBox(height: 2),
            Text(label, style: text.labelSmall),
          ],
        ),
      ),
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
        Text('RECENT ACTIVITY', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
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
          initials: _initials(who),
          tint: AppColors.avatarAmber,
          title: 'Hint · $who',
          subtitle: h.title,
          timestamp: h.createdAt ?? DateTime.now(),
          onTap: (ctx) => ctx.push(AppRoutes.hints),
        ),
      );
    }

    // Records added.
    final List<Record> records =
        ref.watch(recordsProvider).value ?? const <Record>[];
    for (final r in records) {
      out.add(
        _Activity(
          initials: _initials(r.title.isEmpty ? r.type.label : r.title),
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
          initials: _initials(name),
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _Activity {
  const _Activity({
    required this.initials,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.onTap,
  });
  final String initials;
  final Color tint;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final void Function(BuildContext) onTap;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});
  final _Activity activity;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => activity.onTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: activity.tint,
              child: Text(
                activity.initials,
                style: text.labelLarge?.copyWith(color: AppColors.textPrimary),
              ),
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.border),
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

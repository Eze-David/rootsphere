import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/timeline_event.dart';
import '../providers/tree_providers.dart';
import '../widgets/person_editor_sheet.dart';
import '../widgets/photo_actions.dart';
import '../widgets/timeline_event_editor_sheet.dart';

/// Full-screen profile for a person: header, timeline, photo gallery, notes.
class PersonProfileScreen extends ConsumerWidget {
  const PersonProfileScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Person? person = ref.watch(personByIdProvider(personId));

    if (person == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Person not found.')),
      );
    }

    final TextTheme text = Theme.of(context).textTheme;
    final events = _buildTimeline(person);
    final relatives = _relatives(ref, person);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showPersonEditorSheet(context, ref, existing: person),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          _Header(person: person),
          const SizedBox(height: AppSpacing.xl),
          if (relatives.isNotEmpty) ...<Widget>[
            _SectionLabel('FAMILY'),
            const SizedBox(height: AppSpacing.sm),
            _RelativesWrap(
              relatives: relatives,
              onTap: (p) => context.push('/person/${p.id}'),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          Row(
            children: <Widget>[
              Expanded(child: _SectionLabel('TIMELINE')),
              TextButton.icon(
                onPressed: () =>
                    showTimelineEventEditorSheet(context, ref, person),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add event'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (events.isEmpty)
            Text('No dated events yet.', style: text.bodyMedium)
          else
            _Timeline(
              events: events,
              onTapEvent: (event) {
                // Only custom events are editable; birth/death derive from the
                // structured fields (edit those via the person editor).
                if (event.id == '_birth' || event.id == '_death') {
                  showPersonEditorSheet(context, ref, existing: person);
                } else {
                  showTimelineEventEditorSheet(
                    context,
                    ref,
                    person,
                    existing: event,
                  );
                }
              },
            ),
          const SizedBox(height: AppSpacing.xl),
          _SectionLabel('PHOTOS'),
          const SizedBox(height: AppSpacing.sm),
          _PhotoGallery(person: person),
          const SizedBox(height: AppSpacing.xl),
          _SectionLabel('NOTES'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            (person.notes?.trim().isNotEmpty ?? false)
                ? person.notes!
                : 'No notes yet. Tap edit to add some.',
            style: text.bodyLarge?.copyWith(
              color: (person.notes?.trim().isNotEmpty ?? false)
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  /// Derives a chronological timeline from the person's structured fields plus
  /// any custom events.
  List<TimelineEvent> _buildTimeline(Person p) {
    final events = <TimelineEvent>[...p.events];
    if (p.birthDate != null) {
      events.add(TimelineEvent(
        id: '_birth',
        type: LifeEventType.birth,
        title: 'Born',
        date: p.birthDate,
        place: p.birthPlace,
      ));
    }
    if (p.deathDate != null) {
      events.add(TimelineEvent(
        id: '_death',
        type: LifeEventType.death,
        title: 'Died',
        date: p.deathDate,
        place: p.deathPlace,
      ));
    }
    events.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return events;
  }

  List<_Relative> _relatives(WidgetRef ref, Person p) {
    final map = ref.watch(personMapProvider);
    final out = <_Relative>[];
    for (final id in p.parentIds) {
      final r = map[id];
      if (r != null) out.add(_Relative(r, 'Parent'));
    }
    for (final id in p.spouseIds) {
      final r = map[id];
      if (r != null) out.add(_Relative(r, 'Spouse'));
    }
    for (final c in map.values.where((c) => c.parentIds.contains(p.id))) {
      out.add(_Relative(c, 'Child'));
    }
    return out;
  }
}

class _Relative {
  _Relative(this.person, this.relation);
  final Person person;
  final String relation;
}

class _Header extends ConsumerWidget {
  const _Header({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasPhoto = person.photoUrl != null && person.photoUrl!.isNotEmpty;
    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            AdaptiveAvatar(reference: person.photoUrl, radius: 44),
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => hasPhoto
                      ? _showAvatarMenu(context, ref)
                      : PhotoActions.setProfilePhoto(context, ref, person),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 16,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(person.fullName, style: text.headlineMedium, textAlign: TextAlign.center),
        if (person.lifespan.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(person.lifespan, style: text.bodyLarge?.copyWith(color: AppColors.textSecondary)),
        ],
        if (person.birthPlace != null) ...<Widget>[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.place_outlined, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(person.birthPlace!, style: text.bodyMedium),
            ],
          ),
        ],
      ],
    );
  }

  void _showAvatarMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Change profile photo'),
              onTap: () {
                Navigator.pop(ctx);
                PhotoActions.setProfilePhoto(context, ref, person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Remove profile photo',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                PhotoActions.removeProfilePhoto(ref, person);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.labelSmall);
  }
}

class _RelativesWrap extends StatelessWidget {
  const _RelativesWrap({required this.relatives, required this.onTap});
  final List<_Relative> relatives;
  final ValueChanged<Person> onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final r in relatives)
          ActionChip(
            avatar: const Icon(Icons.person_outline, size: 18),
            label: Text('${r.person.fullName} · ${r.relation}', style: text.bodyMedium),
            onPressed: () => onTap(r.person),
          ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events, required this.onTapEvent});
  final List<TimelineEvent> events;
  final ValueChanged<TimelineEvent> onTapEvent;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        for (int i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (i != events.length - 1)
                      Expanded(
                        child: Container(width: 2, color: AppColors.border),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: InkWell(
                    onTap: () => onTapEvent(events[i]),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppSpacing.lg,
                        right: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            events[i].date != null
                                ? Person.fmtDate(events[i].date!)
                                : '—',
                            style: text.labelLarge
                                ?.copyWith(color: AppColors.primary),
                          ),
                          Text(events[i].title, style: text.titleMedium),
                          if (events[i].place != null)
                            Text(events[i].place!, style: text.bodyMedium),
                          if (events[i].description != null)
                            Text(events[i].description!, style: text.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PhotoGallery extends ConsumerWidget {
  const _PhotoGallery({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: person.photoGallery.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          if (i == 0) return _AddTile(person: person);
          final String reference = person.photoGallery[i - 1];
          return GestureDetector(
            onTap: () => _showPhotoOptions(context, ref, reference),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: AdaptiveImage(
                reference: reference,
                width: 96,
                height: 96,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPhotoOptions(
    BuildContext context,
    WidgetRef ref,
    String reference,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Set as profile photo'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(treeRepositoryProvider).upsertPerson(
                      person.copyWith(photoUrl: reference),
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Remove photo',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                PhotoActions.removeGalleryPhoto(context, ref, person, reference);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends ConsumerWidget {
  const _AddTile({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => PhotoActions.addGalleryPhoto(context, ref, person),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.add_photo_alternate_outlined,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 4),
            Text('Add', style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

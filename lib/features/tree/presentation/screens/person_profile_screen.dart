import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../../assistant/domain/entities/assistant_result.dart';
import '../../../assistant/presentation/providers/assistant_providers.dart';
import '../../../records/domain/entities/record.dart';
import '../../../records/presentation/providers/record_providers.dart';
import '../../data/services/geocoding_service.dart';
import '../../domain/entities/edit_history_entry.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/timeline_event.dart';
import '../providers/tree_providers.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/osm_attribution.dart';
import '../widgets/person_actions_sheet.dart';
import '../widgets/person_editor_sheet.dart';
import 'tree_map_screen.dart';
import '../widgets/photo_actions.dart';
import '../widgets/timeline_event_editor_sheet.dart';
import '../widgets/video_player_screen.dart';
import '../widgets/voice_recorder_sheet.dart';

/// Full-screen profile for a person: header, timeline, photo gallery, notes.
class PersonProfileScreen extends ConsumerWidget {
  PersonProfileScreen({super.key, required this.personId});

  final String personId;

  final GlobalKey _familyKey = GlobalKey();
  final GlobalKey _mediaKey = GlobalKey();

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
    final events = _personTimeline(person);
    final relatives = _relatives(ref, person);
    final int mediaCount =
        person.photoGallery.length +
        person.videoGallery.length +
        person.voiceNotes.length;
    final int recordCount = ref
        .watch(recordsForPersonProvider(person.id))
        .length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.onPrimary,
        title: const Text(
          'Profile',
          style: TextStyle(color: AppColors.onPrimary),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () =>
                showPersonEditorSheet(context, ref, existing: person),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _HeroHeader(
            person: person,
            familyCount: relatives.length,
            recordCount: recordCount,
            mediaCount: mediaCount,
            onFamilyTap: relatives.isEmpty
                ? null
                : () => _scrollToSection(_familyKey),
            onRecordsTap: () => _showPersonRecordsSheet(context, ref, person),
            onMediaTap: () => _scrollToSection(_mediaKey),
            onTreeTap: () {
              setFocusPerson(ref, person.id);
              context.go(AppRoutes.tree);
            },
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SectionCard(
                  key: _familyKey,
                  icon: Icons.diversity_3_outlined,
                  title: 'FAMILY',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Find existing person',
                        icon: const Icon(Icons.search, size: 20),
                        onPressed: () =>
                            _showFindPersonSheet(context, ref, person),
                      ),
                      IconButton(
                        tooltip: 'Add family member',
                        icon: const Icon(
                          Icons.person_add_alt_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            _showAddRelativeSheet(context, ref, person),
                      ),
                    ],
                  ),
                  child: relatives.isEmpty
                      ? Text(
                          'No family linked yet.',
                          style: text.bodyLarge?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        )
                      : _RelativesWrap(
                          relatives: relatives,
                          onTap: (p) => context.push('/person/${p.id}'),
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_hasDetails(person)) ...<Widget>[
                  _SectionCard(
                    icon: Icons.badge_outlined,
                    title: 'DETAILS',
                    child: _DetailsSection(person: person),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _SectionCard(
                  icon: Icons.auto_awesome_outlined,
                  title: 'AI RESEARCH ASSISTANT',
                  child: _ResearchAssistantSection(
                    person: person,
                    relatives: relatives,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionCard(
                  icon: Icons.timeline_outlined,
                  title: 'TIMELINE',
                  trailing: TextButton.icon(
                    onPressed: () =>
                        showTimelineEventEditorSheet(context, ref, person),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add event'),
                  ),
                  child: events.isEmpty
                      ? Text('No dated events yet.', style: text.bodyMedium)
                      : _Timeline(
                          events: events,
                          onTapEvent: (event) {
                            // Only custom events are editable; birth/death
                            // derive from the structured fields (edit those
                            // via the person editor).
                            if (event.id == '_birth' ||
                                event.id == '_death') {
                              showPersonEditorSheet(
                                context,
                                ref,
                                existing: person,
                              );
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
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_hasResearch(person)) ...<Widget>[
                  _SectionCard(
                    icon: Icons.travel_explore_outlined,
                    title: 'RESEARCH',
                    child: _ResearchSection(person: person),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (person.location.isNotEmpty) ...<Widget>[
                  _SectionCard(
                    icon: Icons.map_outlined,
                    title: 'MAP',
                    child: _LocationMapCard(
                      location: person.location,
                      personId: person.id,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _SectionCard(
                  key: _mediaKey,
                  icon: Icons.perm_media_outlined,
                  title: 'MEDIA',
                  child: _MediaGallery(person: person),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionCard(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'NOTES',
                  child: Text(
                    (person.notes?.trim().isNotEmpty ?? false)
                        ? person.notes!
                        : 'No notes yet. Tap edit to add some.',
                    style: text.bodyLarge?.copyWith(
                      color: (person.notes?.trim().isNotEmpty ?? false)
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionCard(
                  icon: Icons.history,
                  title: 'EDIT HISTORY',
                  child: _EditHistory(personId: person.id),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Walks the whole ancestor and descendant chain generation by generation
  /// (grandparents, great-grandparents, ... and grandchildren,
  /// great-grandchildren, ...), not just direct parents/children, labelling
  /// each with the standard genealogical term for how many generations
  /// removed they are.
  List<_Relative> _relatives(WidgetRef ref, Person p) {
    final map = ref.watch(personMapProvider);
    final out = <_Relative>[];
    final Set<String> visited = <String>{p.id};

    List<String> ancestorGen = p.parentIds;
    int depth = 1;
    while (ancestorGen.isNotEmpty) {
      final List<String> nextGen = <String>[];
      for (final id in ancestorGen) {
        if (!visited.add(id)) continue;
        final Person? r = map[id];
        if (r == null) continue;
        out.add(_Relative(r, _ancestorLabel(depth, r.sex)));
        nextGen.addAll(r.parentIds);
      }
      ancestorGen = nextGen;
      depth++;
    }

    for (final s in map.values.where(
      (s) => s.parentIds.any(p.parentIds.contains),
    )) {
      if (!visited.add(s.id)) continue;
      out.add(
        _Relative(
          s,
          switch (s.sex) {
            Sex.male => 'Brother',
            Sex.female => 'Sister',
            Sex.unknown => 'Sibling',
          },
        ),
      );
    }

    for (final id in p.spouseIds) {
      final Person? r = map[id];
      if (r != null) {
        out.add(
          _Relative(
            r,
            switch (r.sex) {
              Sex.male => 'Husband',
              Sex.female => 'Wife',
              Sex.unknown => 'Spouse',
            },
          ),
        );
      }
    }

    List<String> descendantGen = map.values
        .where((c) => c.parentIds.contains(p.id))
        .map((c) => c.id)
        .toList();
    depth = 1;
    while (descendantGen.isNotEmpty) {
      final List<String> nextGen = <String>[];
      for (final id in descendantGen) {
        if (!visited.add(id)) continue;
        final Person? r = map[id];
        if (r == null) continue;
        out.add(_Relative(r, _descendantLabel(depth, r.sex)));
        nextGen.addAll(
          map.values.where((c) => c.parentIds.contains(id)).map((c) => c.id),
        );
      }
      descendantGen = nextGen;
      depth++;
    }

    return out;
  }

  String _ancestorLabel(int depth, Sex sex) => _generationalLabel(
    depth: depth,
    male: 'father',
    female: 'mother',
    neutral: 'parent',
    sex: sex,
  );

  String _descendantLabel(int depth, Sex sex) => _generationalLabel(
    depth: depth,
    male: 'son',
    female: 'daughter',
    neutral: 'child',
    sex: sex,
  );

  /// depth 1 → "Father"/"Son"; depth 2 → "Grandfather"/"Grandson"; depth 3+
  /// → "Great-grandfather"/"Great-great-grandfather"/etc, following standard
  /// genealogical naming.
  String _generationalLabel({
    required int depth,
    required String male,
    required String female,
    required String neutral,
    required Sex sex,
  }) {
    final String noun = switch (sex) {
      Sex.male => male,
      Sex.female => female,
      Sex.unknown => neutral,
    };
    final String label = depth <= 1
        ? noun
        : '${List.filled(depth - 2, 'great-').join()}grand$noun';
    return label[0].toUpperCase() + label.substring(1);
  }

  /// Scrolls the page so the given section (Family/Media, tapped from the
  /// hero stat row) comes into view — both sections already live further
  /// down this same page, so "opening" them means jumping to them.
  void _scrollToSection(GlobalKey key) {
    final BuildContext? ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  /// Records don't have their own section on this page, so the "Records"
  /// stat opens a bottom sheet listing everything citing this person,
  /// each tapping through to its full detail screen.
  void _showPersonRecordsSheet(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) {
    final List<Record> records = ref.read(
      recordsForPersonProvider(person.id),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Records for ${person.fullName}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: records.isEmpty
                      ? Text(
                          'No records linked to this person yet.',
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: records.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: AppSpacing.lg),
                          itemBuilder: (_, i) {
                            final Record r = records[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(r.type.icon),
                              title: Text(r.title),
                              subtitle: Text(r.type.label),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(ctx);
                                context.push('/record/${r.id}');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Quick-add menu for the FAMILY section: creates a brand-new relative
  /// (via the person editor) and links it straight away.
  void _showAddRelativeSheet(BuildContext context, WidgetRef ref, Person person) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.escalator_warning_outlined),
              title: const Text('Add parent'),
              onTap: () {
                Navigator.pop(ctx);
                addNewRelative(context, ref, person, PersonRelation.parent);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Add spouse'),
              onTap: () {
                Navigator.pop(ctx);
                addNewRelative(context, ref, person, PersonRelation.spouse);
              },
            ),
            ListTile(
              leading: const Icon(Icons.child_care_outlined),
              title: const Text('Add child'),
              onTap: () {
                Navigator.pop(ctx);
                addNewRelative(context, ref, person, PersonRelation.child);
              },
            ),
            if (person.parentIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Add sibling'),
                onTap: () {
                  Navigator.pop(ctx);
                  addNewRelative(context, ref, person, PersonRelation.sibling);
                },
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  /// Finds an already-existing person in the tree and links them as a
  /// relative — avoids creating a duplicate record for someone who's
  /// already elsewhere in the tree.
  Future<void> _showFindPersonSheet(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    final List<Person> persons = (ref.read(personsProvider).value ??
            const <Person>[])
        .where((p) => p.id != person.id)
        .toList();
    final Person? found = await showDialog<Person>(
      context: context,
      builder: (ctx) => _FindPersonDialog(persons: persons),
    );
    if (found == null || !context.mounted) return;

    final PersonRelation? relation = await showModalBottomSheet<PersonRelation>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.escalator_warning_outlined),
              title: Text('Link ${found.fullName} as parent'),
              onTap: () => Navigator.pop(ctx, PersonRelation.parent),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text('Link ${found.fullName} as spouse'),
              onTap: () => Navigator.pop(ctx, PersonRelation.spouse),
            ),
            ListTile(
              leading: const Icon(Icons.child_care_outlined),
              title: Text('Link ${found.fullName} as child'),
              onTap: () => Navigator.pop(ctx, PersonRelation.child),
            ),
            if (person.parentIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: Text('Link ${found.fullName} as sibling'),
                onTap: () => Navigator.pop(ctx, PersonRelation.sibling),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (relation == null) return;
    await linkExistingRelative(ref, person, found.id, relation);
  }
}

/// Search dialog for finding an existing person to link as a relative
/// (mirrors the tree screen's "Search people" dialog).
class _FindPersonDialog extends StatefulWidget {
  const _FindPersonDialog({required this.persons});
  final List<Person> persons;

  @override
  State<_FindPersonDialog> createState() => _FindPersonDialogState();
}

class _FindPersonDialogState extends State<_FindPersonDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Person> get _results {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.persons;
    return widget.persons
        .where(
          (p) =>
              p.fullName.toLowerCase().contains(q) ||
              (p.code?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  /// Shows the birth year and/or ID code so a matching search result can be
  /// visually confirmed — most useful when several people share a name.
  Widget? _resultSubtitle(Person p, TextTheme text) {
    final String? code = p.code;
    final String year = p.birthDate != null ? '${p.birthDate!.year}' : '';
    final String label = <String>[
      if (year.isNotEmpty) year,
      if (code != null && code.isNotEmpty) code,
    ].join(' · ');
    return label.isEmpty ? null : Text(label, style: text.bodySmall);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('Find a person', style: text.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name or ID…',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textTertiary,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Text(
                          'No matches.',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final Person p = _results[i];
                          return ListTile(
                            leading: AdaptiveAvatar(
                              reference: p.photoUrl,
                              radius: 18,
                            ),
                            title: Text(p.fullName),
                            subtitle: _resultSubtitle(p, text),
                            onTap: () => Navigator.of(context).pop(p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Derives a chronological timeline from a person's structured fields plus
/// any custom events.
List<TimelineEvent> _personTimeline(Person p) {
  final events = <TimelineEvent>[...p.events];
  if (p.birthDate != null) {
    events.add(
      TimelineEvent(
        id: '_birth',
        type: LifeEventType.birth,
        title: 'Born',
        date: p.birthDate,
        place: p.birthPlace,
      ),
    );
  }
  if (p.deathDate != null) {
    events.add(
      TimelineEvent(
        id: '_death',
        type: LifeEventType.death,
        title: 'Died',
        date: p.deathDate,
        place: p.deathPlace,
      ),
    );
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

class _Relative {
  _Relative(this.person, this.relation);
  final Person person;
  final String relation;
}

bool _hasDetails(Person p) =>
    (p.nickname ?? '').trim().isNotEmpty ||
    (p.otherNames ?? '').trim().isNotEmpty ||
    (p.religion ?? '').trim().isNotEmpty ||
    (p.deathPlace ?? '').trim().isNotEmpty ||
    (p.occupation ?? '').trim().isNotEmpty ||
    (p.education ?? '').trim().isNotEmpty ||
    (p.language ?? '').trim().isNotEmpty ||
    p.location.isNotEmpty;

bool _hasResearch(Person p) =>
    (p.researchNotes ?? '').trim().isNotEmpty ||
    (p.researchQuestions ?? '').trim().isNotEmpty;

/// A map card centred on the person's location (geocoded via the `geocode`
/// Edge Function). Falls back to a plain placeholder — matching the original
/// design mock — while resolving, or when the place can't be found / the app
/// is offline.
class _LocationMapCard extends ConsumerStatefulWidget {
  const _LocationMapCard({required this.location, required this.personId});
  final String location;
  final String personId;

  @override
  ConsumerState<_LocationMapCard> createState() => _LocationMapCardState();
}

class _LocationMapCardState extends ConsumerState<_LocationMapCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GeocodeResult?> geocode = ref.watch(
      geocodeProvider(widget.location),
    );
    final GeocodeResult? result = geocode.value;

    // The embedded map itself is inert (see the IgnorePointer below) — the
    // whole card is one big "open the full map" tap target — so hover is
    // tracked here, at the card level, rather than on the (unhittable) pin.
    return MouseRegion(
      onEnter: result == null ? null : (_) => setState(() => _hovered = true),
      onExit: result == null ? null : (_) => setState(() => _hovered = false),
      cursor: result == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
              color: AppColors.textTertiary.withValues(alpha: 0.3),
            ),
          ),
          child: result == null
              ? _placeholder(context, loading: geocode.isLoading)
              : _map(context, result),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, {required bool loading}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        loading
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.map_outlined,
                size: 40,
                color: AppColors.textTertiary.withValues(alpha: 0.6),
              ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.location,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _map(BuildContext context, GeocodeResult result) {
    final LatLng point = LatLng(result.lat, result.lon);
    return GestureDetector(
      onTap: () => _expand(context),
      child: Stack(
        children: <Widget>[
          IgnorePointer(
            // flutter_map needs bounded, non-zero constraints to compute tile
            // ranges. Both unbounded (infinite) and a genuine 0×0 size — the
            // latter happens when native platform resolution isn't available
            // yet on the very first frame(s) — produce Infinity/NaN and
            // crash; `isFinite` alone doesn't catch zero, so check explicitly.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool sizeReady =
                    constraints.maxWidth.isFinite &&
                    constraints.maxHeight.isFinite &&
                    constraints.maxWidth > 0 &&
                    constraints.maxHeight > 0;
                if (!sizeReady) {
                  return const SizedBox.shrink();
                }
                return FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 12,
                    minZoom: 2,
                    maxZoom: 18,
                  ),
                  children: <Widget>[
                    TileLayer(
                      // See tree_map_screen.dart — the raw OSM tile server
                      // throttles real app traffic; CARTO's free CDN doesn't.
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      subdomains: const <String>['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.rootsphere.app',
                      // Avoids "setState() called during build" from the
                      // default fade-in animation.
                      tileDisplay: const TileDisplay.instantaneous(),
                    ),
                    MarkerLayer(
                      markers: <Marker>[
                        Marker(
                          point: point,
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.location_on,
                            color: _hovered
                                ? AppColors.sunGold
                                : AppColors.primary,
                            size: _hovered ? 40 : 36,
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
          Positioned(
            right: AppSpacing.sm,
            top: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(
                Icons.open_in_full,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _expand(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TreeMapScreen(focusPersonId: widget.personId),
      ),
    );
  }
}

/// Read-only list of the person's extra structured fields (religion, death
/// place, residence location).
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> rows = <Widget>[];

    void add(IconData icon, String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label.toUpperCase(), style: text.labelSmall),
                    Text(value.trim(), style: text.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    add(Icons.badge_outlined, 'Nickname', person.nickname);
    add(Icons.text_fields_outlined, 'Other names', person.otherNames);
    add(Icons.place_outlined, 'Death place', person.deathPlace);
    add(Icons.church_outlined, 'Religion', person.religion);
    add(Icons.work_outline, 'Occupation', person.occupation);
    add(Icons.school_outlined, 'Education', person.education);
    add(Icons.translate, 'Language', person.language);
    add(
      Icons.public,
      'Location',
      person.location.isEmpty ? null : person.location,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// Research notes and open questions for the person.
class _ResearchSection extends StatelessWidget {
  const _ResearchSection({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> children = <Widget>[];

    if ((person.researchNotes ?? '').trim().isNotEmpty) {
      children.addAll(<Widget>[
        Text('FINDINGS & NOTES'.toUpperCase(), style: text.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(person.researchNotes!, style: text.bodyLarge),
      ]);
    }

    if ((person.researchQuestions ?? '').trim().isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.md));
      }
      children.addAll(<Widget>[
        Text('OPEN QUESTIONS'.toUpperCase(), style: text.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(person.researchQuestions!, style: text.bodyLarge),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Claude-powered research actions for this person. Results are ephemeral
/// (shown in a bottom sheet) rather than persisted — unlike the document-level
/// actions on the Record Detail screen, these synthesise the whole tree/person
/// context rather than a single cacheable document.
class _ResearchAssistantSection extends ConsumerStatefulWidget {
  const _ResearchAssistantSection({
    required this.person,
    required this.relatives,
  });
  final Person person;
  final List<_Relative> relatives;

  @override
  ConsumerState<_ResearchAssistantSection> createState() =>
      _ResearchAssistantSectionState();
}

class _ResearchAssistantSectionState
    extends ConsumerState<_ResearchAssistantSection> {
  String? _runningAction;

  Future<void> _run(String action, Future<void> Function() body) async {
    setState(() => _runningAction = action);
    await body();
    if (mounted) setState(() => _runningAction = null);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSheet(String title, List<Widget> children) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: children.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: AppSpacing.lg),
                  itemBuilder: (_, i) => children[i],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _suggestAncestors() => _run('ancestors', () async {
    final res = await ref
        .read(assistantServiceProvider)
        .suggestAncestors(
          scope: widget.person.id,
          person: widget.person,
          relatives: widget.relatives.map((r) => r.person).toList(),
        );
    if (!mounted) return;
    if (!res.available) {
      _showMessage(res.message ?? 'Could not generate suggestions.');
      return;
    }
    final items = res.data ?? const <AncestorSuggestion>[];
    if (items.isEmpty) {
      _showMessage('No suggestions right now — the tree looks complete.');
      return;
    }
    await _showSheet('Suggested ancestors', <Widget>[
      for (final s in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_add_alt_outlined),
          title: Text(s.relation),
          subtitle: Text(s.reasoning),
          trailing: Text('${s.confidence}%'),
        ),
    ]);
  });

  Future<void> _generateTimeline() => _run('timeline', () async {
    final events = _personTimeline(widget.person);
    final records = ref.read(recordsForPersonProvider(widget.person.id));
    final res = await ref
        .read(assistantServiceProvider)
        .generateTimeline(
          scope: widget.person.id,
          person: widget.person,
          events: events,
          records: records,
        );
    if (!mounted) return;
    if (!res.available) {
      _showMessage(res.message ?? 'Could not generate a timeline.');
      return;
    }
    final items = res.data ?? const <TimelineEntry>[];
    if (items.isEmpty) {
      _showMessage('Not enough information to build a timeline yet.');
      return;
    }
    await _showSheet('Generated timeline', <Widget>[
      for (final e in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 16,
            child: Text(
              e.year?.toString() ?? '?',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          title: Text(e.title),
          subtitle: Text(e.description),
        ),
    ]);
  });

  Future<void> _suggestMissingRecords() => _run('missingRecords', () async {
    final records = ref.read(recordsForPersonProvider(widget.person.id));
    final existingTypes = records.map((r) => r.type).toSet().toList();
    final res = await ref
        .read(assistantServiceProvider)
        .suggestMissingRecords(
          scope: widget.person.id,
          person: widget.person,
          existingTypes: existingTypes,
        );
    if (!mounted) return;
    if (!res.available) {
      _showMessage(res.message ?? 'Could not generate suggestions.');
      return;
    }
    final items = res.data ?? const <MissingRecordSuggestion>[];
    if (items.isEmpty) {
      _showMessage('No obvious record gaps found.');
      return;
    }
    await _showSheet('Suggested record searches', <Widget>[
      for (final s in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.find_in_page_outlined),
          title: Text(_recordTypeLabel(s.type)),
          subtitle: Text(s.reasoning),
          trailing: Text('${s.confidence}%'),
        ),
    ]);
  });

  Future<void> _researchRecommendations() => _run('research', () async {
    final records = ref.read(recordsForPersonProvider(widget.person.id));
    final res = await ref
        .read(assistantServiceProvider)
        .researchRecommendations(
          scope: widget.person.id,
          person: widget.person,
          relatives: widget.relatives.map((r) => r.person).toList(),
          records: records,
        );
    if (!mounted) return;
    if (!res.available) {
      _showMessage(res.message ?? 'Could not generate recommendations.');
      return;
    }
    final items = res.data ?? const <ResearchRecommendation>[];
    if (items.isEmpty) {
      _showMessage('No recommendations right now.');
      return;
    }
    await _showSheet('Research recommendations', <Widget>[
      for (final r in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(r.title),
          subtitle: Text(r.description),
        ),
    ]);
  });

  String _recordTypeLabel(String typeName) {
    return RecordType.values
        .firstWhere((t) => t.name == typeName, orElse: () => RecordType.other)
        .label;
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _runningAction != null;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        _AssistantActionChip(
          label: 'Suggest ancestors',
          icon: Icons.person_add_alt_outlined,
          loading: _runningAction == 'ancestors',
          onPressed: busy ? null : _suggestAncestors,
        ),
        _AssistantActionChip(
          label: 'Generate timeline',
          icon: Icons.timeline_outlined,
          loading: _runningAction == 'timeline',
          onPressed: busy ? null : _generateTimeline,
        ),
        _AssistantActionChip(
          label: 'Suggest missing records',
          icon: Icons.find_in_page_outlined,
          loading: _runningAction == 'missingRecords',
          onPressed: busy ? null : _suggestMissingRecords,
        ),
        _AssistantActionChip(
          label: 'Research recommendations',
          icon: Icons.lightbulb_outline,
          loading: _runningAction == 'research',
          onPressed: busy ? null : _researchRecommendations,
        ),
      ],
    );
  }
}

class _AssistantActionChip extends StatelessWidget {
  const _AssistantActionChip({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

/// Audit log of edits made to this person (who, when and why).
class _EditHistory extends ConsumerWidget {
  const _EditHistory({required this.personId});
  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<EditHistoryEntry>> async = ref.watch(
      personEditHistoryProvider(personId),
    );

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('Loading…', style: text.bodyMedium),
      ),
      error: (_, _) =>
          Text('Could not load edit history.', style: text.bodyMedium),
      data: (entries) {
        if (entries.isEmpty) {
          return Text(
            'No edits recorded yet.',
            style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
          );
        }
        return Column(
          children: <Widget>[
            for (final e in entries) _EditHistoryTile(entry: e),
          ],
        );
      },
    );
  }
}

/// Older rows can have a raw email baked into `editor_name` (from before
/// the editor-name fallback preferred the email's local part) — strip the
/// domain at display time so history never shows a full email address.
String _displayEditorName(String? editorName) {
  final String trimmed = editorName?.trim() ?? '';
  if (trimmed.isEmpty) return 'Someone';
  final int at = trimmed.indexOf('@');
  return at > 0 ? trimmed.substring(0, at) : trimmed;
}

class _EditHistoryTile extends StatelessWidget {
  const _EditHistoryTile({required this.entry});
  final EditHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String when = Person.fmtDate(entry.createdAt);
    final String who = _displayEditorName(entry.editorName);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.history,
                size: 16,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('$who · $when', style: text.labelLarge)),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.reason, style: text.bodyLarge),
          if (entry.changedFields.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Changed: ${entry.changedFields.join(', ')}',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Cover-banner header: gradient banner behind the app bar, an avatar
/// overlapping its bottom edge, and a quick-stat row (family/records/media)
/// beneath the name — replaces the old plain centered header.
class _HeroHeader extends ConsumerWidget {
  const _HeroHeader({
    required this.person,
    required this.familyCount,
    required this.recordCount,
    required this.mediaCount,
    this.onFamilyTap,
    this.onRecordsTap,
    this.onMediaTap,
    this.onTreeTap,
  });

  final Person person;
  final int familyCount;
  final int recordCount;
  final int mediaCount;
  final VoidCallback? onFamilyTap;
  final VoidCallback? onRecordsTap;
  final VoidCallback? onMediaTap;
  final VoidCallback? onTreeTap;

  static const double _avatarRadius = 48;
  static const double _bannerContentHeight = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasPhoto =
        person.photoUrl != null && person.photoUrl!.isNotEmpty;
    final double topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final double bannerHeight = topInset + _bannerContentHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: bannerHeight + _avatarRadius,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                height: bannerHeight,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      AppColors.primary,
                      AppColors.primaryHover,
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(AppSpacing.radiusXl),
                  ),
                ),
              ),
              Positioned(
                top: bannerHeight - _avatarRadius,
                left: 0,
                right: 0,
                child: Center(
                  child: Stack(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                          shape: BoxShape.circle,
                        ),
                        child: AdaptiveAvatar(
                          reference: person.photoUrl,
                          radius: _avatarRadius,
                        ),
                      ),
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
                                : PhotoActions.setProfilePhoto(
                                    context,
                                    ref,
                                    person,
                                  ),
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
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          person.fullName,
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (person.lifespan.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            person.lifespan,
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (person.birthPlace != null) ...<Widget>[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(person.birthPlace!, style: text.bodyMedium),
            ],
          ),
        ],
        if ((person.code ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Material(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                onTap: () => _copyCode(context, person.code!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        person.code!,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _HeroStats(
          familyCount: familyCount,
          recordCount: recordCount,
          mediaCount: mediaCount,
          onFamilyTap: onFamilyTap,
          onRecordsTap: onRecordsTap,
          onMediaTap: onMediaTap,
          onTreeTap: onTreeTap,
        ),
      ],
    );
  }

  Future<void> _copyCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied "$code" to clipboard.')));
  }

  void _showAvatarMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
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
              title: const Text(
                'Remove profile photo',
                style: TextStyle(color: AppColors.error),
              ),
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

/// Family/Records/Media quick-stat row shown under the hero header.
class _HeroStats extends StatelessWidget {
  const _HeroStats({
    required this.familyCount,
    required this.recordCount,
    required this.mediaCount,
    this.onFamilyTap,
    this.onRecordsTap,
    this.onMediaTap,
    this.onTreeTap,
  });

  final int familyCount;
  final int recordCount;
  final int mediaCount;
  final VoidCallback? onFamilyTap;
  final VoidCallback? onRecordsTap;
  final VoidCallback? onMediaTap;
  final VoidCallback? onTreeTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _StatItem(
          icon: Icons.diversity_3_outlined,
          value: familyCount,
          label: 'Family',
          onTap: onFamilyTap,
        ),
        _StatDivider(),
        _StatItem(
          icon: Icons.description_outlined,
          value: recordCount,
          label: 'Records',
          onTap: onRecordsTap,
        ),
        _StatDivider(),
        _StatItem(
          icon: Icons.perm_media_outlined,
          value: mediaCount,
          label: 'Media',
          onTap: onMediaTap,
        ),
        _StatDivider(),
        _StatItem(
          icon: Icons.account_tree_outlined,
          value: null,
          label: 'Tree',
          onTap: onTreeTap,
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final int? value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(height: 2),
              if (value != null)
                Text(
                  '$value',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Text(
                label,
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    color: AppColors.border,
  );
}

/// Elevated rounded card used to wrap every section on the profile screen
/// (Family, Details, Timeline, etc.) with a consistent icon + title header.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
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
          Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              onTap: () => onTap(r.person),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AdaptiveAvatar(reference: r.person.photoUrl, radius: 14),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          r.person.fullName,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          r.relation,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
                            style: text.labelLarge?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          Text(events[i].title, style: text.titleMedium),
                          if (events[i].place != null)
                            Text(events[i].place!, style: text.bodyMedium),
                          if (events[i].description != null)
                            Text(
                              events[i].description!,
                              style: text.bodyMedium,
                            ),
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

/// A single media reference together with its derived kind.
class _MediaItem {
  const _MediaItem(this.reference, this.kind);
  final String reference;
  final MediaKind kind;
}

/// Combined media gallery: photos, videos and voice notes shown together with
/// a single "Add" entry point.
class _MediaGallery extends ConsumerWidget {
  const _MediaGallery({required this.person});
  final Person person;

  List<_MediaItem> get _items => <_MediaItem>[
    for (final r in person.photoGallery) _MediaItem(r, MediaKind.image),
    for (final r in person.videoGallery) _MediaItem(r, MediaKind.video),
    for (final r in person.voiceNotes) _MediaItem(r, MediaKind.audio),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<_MediaItem> items = _items;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          if (i == 0) return _AddTile(person: person);
          final _MediaItem item = items[i - 1];
          return GestureDetector(
            onTap: () => _showOptions(context, ref, item),
            child: _MediaTile(item: item),
          );
        },
      ),
    );
  }

  Future<void> _open(BuildContext context, _MediaItem item) async {
    switch (item.kind) {
      case MediaKind.video:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(reference: item.reference),
          ),
        );
        break;
      case MediaKind.audio:
        await showAudioPlayerSheet(context, reference: item.reference);
        break;
      case MediaKind.image:
      case MediaKind.other:
        break;
    }
  }

  void _showOptions(BuildContext context, WidgetRef ref, _MediaItem item) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            if (item.kind == MediaKind.image)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Set as profile photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(treeRepositoryProvider)
                      .upsertPerson(person.copyWith(photoUrl: item.reference));
                },
              ),
            if (item.kind == MediaKind.video || item.kind == MediaKind.audio)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  item.kind == MediaKind.video
                      ? 'Play video'
                      : 'Play voice note',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _open(context, item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: Text(
                _removeLabel(item.kind),
                style: const TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                switch (item.kind) {
                  case MediaKind.image:
                    PhotoActions.removeGalleryPhoto(
                      context,
                      ref,
                      person,
                      item.reference,
                    );
                    break;
                  case MediaKind.video:
                    PhotoActions.removeVideo(ref, person, item.reference);
                    break;
                  case MediaKind.audio:
                    PhotoActions.removeVoiceNote(ref, person, item.reference);
                    break;
                  case MediaKind.other:
                    break;
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  String _removeLabel(MediaKind kind) {
    switch (kind) {
      case MediaKind.video:
        return 'Remove video';
      case MediaKind.audio:
        return 'Remove voice note';
      case MediaKind.image:
      case MediaKind.other:
        return 'Remove photo';
    }
  }
}

/// Renders a single media tile by kind: photo thumbnail, video preview with a
/// play badge, or a voice-note tile.
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item});
  final _MediaItem item;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case MediaKind.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AdaptiveImage(
            reference: item.reference,
            width: 96,
            height: 96,
          ),
        );
      case MediaKind.video:
        return _Badged(
          color: AppColors.primary,
          icon: Icons.play_arrow,
          label: 'Video',
        );
      case MediaKind.audio:
        return _Badged(
          color: AppColors.primaryHover,
          icon: Icons.graphic_eq,
          label: 'Voice',
        );
      case MediaKind.other:
        return _Badged(
          color: AppColors.textTertiary,
          icon: Icons.insert_drive_file_outlined,
          label: 'File',
        );
    }
  }
}

class _Badged extends StatelessWidget {
  const _Badged({required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(label, style: text.bodySmall?.copyWith(color: color)),
        ],
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
      onTap: () => _showAddMenu(context, ref),
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
            const Icon(Icons.add, color: AppColors.textTertiary),
            const SizedBox(height: 4),
            Text('Add', style: text.bodyMedium),
          ],
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Add photo'),
              onTap: () {
                Navigator.pop(ctx);
                PhotoActions.addGalleryPhoto(context, ref, person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Add video'),
              onTap: () {
                Navigator.pop(ctx);
                PhotoActions.addGalleryVideo(context, ref, person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic_none_outlined),
              title: const Text('Record voice note'),
              onTap: () async {
                Navigator.pop(ctx);
                final String? path = await showVoiceRecorderSheet(context);
                if (path != null && context.mounted) {
                  await PhotoActions.saveVoiceNote(context, ref, person, path);
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

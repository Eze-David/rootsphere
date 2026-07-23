import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

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
import '../widgets/person_editor_sheet.dart';
import 'tree_map_screen.dart';
import '../widgets/photo_actions.dart';
import '../widgets/timeline_event_editor_sheet.dart';
import '../widgets/video_player_screen.dart';
import '../widgets/voice_recorder_sheet.dart';

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
    final events = _personTimeline(person);
    final relatives = _relatives(ref, person);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
          if (_hasDetails(person)) ...<Widget>[
            _SectionLabel('DETAILS'),
            const SizedBox(height: AppSpacing.sm),
            _DetailsSection(person: person),
            const SizedBox(height: AppSpacing.xl),
          ],
          _SectionLabel('AI RESEARCH ASSISTANT'),
          const SizedBox(height: AppSpacing.sm),
          _ResearchAssistantSection(person: person, relatives: relatives),
          const SizedBox(height: AppSpacing.xl),
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
          if (_hasResearch(person)) ...<Widget>[
            _SectionLabel('RESEARCH'),
            const SizedBox(height: AppSpacing.sm),
            _ResearchSection(person: person),
            const SizedBox(height: AppSpacing.xl),
          ],
          if (person.location.isNotEmpty) ...<Widget>[
            _SectionLabel('MAP'),
            const SizedBox(height: AppSpacing.sm),
            _LocationMapCard(location: person.location, personId: person.id),
            const SizedBox(height: AppSpacing.xl),
          ],
          _SectionLabel('MEDIA'),
          const SizedBox(height: AppSpacing.sm),
          _MediaGallery(person: person),
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
          const SizedBox(height: AppSpacing.xl),
          _SectionLabel('EDIT HISTORY'),
          const SizedBox(height: AppSpacing.sm),
          _EditHistory(personId: person.id),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
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

class _EditHistoryTile extends StatelessWidget {
  const _EditHistoryTile({required this.entry});
  final EditHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String when = Person.fmtDate(entry.createdAt);
    final String who = (entry.editorName?.trim().isNotEmpty ?? false)
        ? entry.editorName!.trim()
        : 'Someone';
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

class _Header extends ConsumerWidget {
  const _Header({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasPhoto =
        person.photoUrl != null && person.photoUrl!.isNotEmpty;
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
        Text(
          person.fullName,
          style: text.headlineMedium,
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
          Material(
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
        ],
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
            label: Text(
              '${r.person.fullName} · ${r.relation}',
              style: text.bodyMedium,
            ),
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

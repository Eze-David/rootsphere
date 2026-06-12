import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/person.dart';
import '../providers/tree_providers.dart';

/// Bottom-sheet form to create or edit a [Person].
///
/// Pass [existing] to edit, or [treeId] + optional link callbacks to create.
///
/// When adding a relative, pass [relationLabel] (e.g. "Add parent") and the
/// [relativeOf] anchor name so the sheet makes the relationship clear. An
/// optional [prefillSurname] seeds the surname field (handy for children).
///
/// Pass [enableLinking] to show an "Add to tree" section that lets the user
/// optionally connect the new person to an existing one at creation time (used
/// by the top-bar `+`). Linking is performed by the editor itself.
///
/// Returns the saved [Person] (already persisted) or null if cancelled.
Future<Person?> showPersonEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  Person? existing,
  String? treeId,
  String? relationLabel,
  String? relativeOf,
  String? prefillSurname,
  bool enableLinking = false,
}) {
  return showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _PersonEditor(
      existing: existing,
      treeId: treeId ?? existing?.treeId ?? 'okonkwo',
      relationLabel: relationLabel,
      relativeOf: relativeOf,
      prefillSurname: prefillSurname,
      enableLinking: enableLinking,
    ),
  );
}

/// How a newly-created person should be connected to an existing one.
enum _LinkRelation { none, child, parent, spouse }

class _PersonEditor extends ConsumerStatefulWidget {
  const _PersonEditor({
    this.existing,
    required this.treeId,
    this.relationLabel,
    this.relativeOf,
    this.prefillSurname,
    this.enableLinking = false,
  });
  final Person? existing;
  final String treeId;
  final String? relationLabel;
  final String? relativeOf;
  final String? prefillSurname;
  final bool enableLinking;

  @override
  ConsumerState<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends ConsumerState<_PersonEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _given;
  late final TextEditingController _surname;
  late final TextEditingController _otherNames;
  late final TextEditingController _nickname;
  late final TextEditingController _suffix;
  late final TextEditingController _birthPlace;
  late final TextEditingController _notes;
  late Sex _sex;
  DateTime? _birthDate;
  DateTime? _deathDate;
  bool _saving = false;

  // Optional in-form linking (top-bar `+` flow).
  _LinkRelation _linkRelation = _LinkRelation.none;
  String? _anchorId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _given = TextEditingController(text: p?.givenName ?? '');
    _surname = TextEditingController(
      text: p?.surname ?? widget.prefillSurname ?? '',
    );
    _otherNames = TextEditingController(text: p?.otherNames ?? '');
    _nickname = TextEditingController(text: p?.nickname ?? '');
    _suffix = TextEditingController(text: p?.suffix ?? '');
    _birthPlace = TextEditingController(text: p?.birthPlace ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _sex = p?.sex ?? Sex.unknown;
    _birthDate = p?.birthDate;
    _deathDate = p?.deathDate;
  }

  @override
  void dispose() {
    _given.dispose();
    _surname.dispose();
    _otherNames.dispose();
    _nickname.dispose();
    _suffix.dispose();
    _birthPlace.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool birth}) async {
    final DateTime initial = (birth ? _birthDate : _deathDate) ?? DateTime(1950);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1700),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (birth) {
          _birthDate = picked;
        } else {
          _deathDate = picked;
        }
      });
    }
  }

  /// Turns a relation label ("Add parent") into a contextual preposition
  /// phrase shown under the title ("Parent of …").
  String _relationPreposition(String? label) {
    final String l = (label ?? '').toLowerCase();
    if (l.contains('child')) return 'Child of';
    if (l.contains('parent')) return 'Parent of';
    if (l.contains('spouse')) return 'Spouse of';
    return 'Related to';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repo = ref.read(treeRepositoryProvider);
    final String id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();

    final Person person = (widget.existing ??
            Person(id: id, treeId: widget.treeId, givenName: ''))
        .copyWith(
      givenName: _given.text.trim(),
      surname: _surname.text.trim(),
      otherNames: _otherNames.text.trim().isEmpty ? null : _otherNames.text.trim(),
      nickname: _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
      suffix: _suffix.text.trim().isEmpty ? null : _suffix.text.trim(),
      sex: _sex,
      birthDate: _birthDate,
      deathDate: _deathDate,
      birthPlace: _birthPlace.text.trim().isEmpty ? null : _birthPlace.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    await repo.upsertPerson(person);
    await _applyLink(repo, person);
    if (mounted) Navigator.pop(context, person);
  }

  /// Links the newly-created [person] to the chosen anchor, when the in-form
  /// "Add to tree" picker was used.
  Future<void> _applyLink(dynamic repo, Person person) async {
    if (_isEdit || _linkRelation == _LinkRelation.none) return;
    final String? anchorId = _anchorId;
    if (anchorId == null) return;

    final Map<String, Person> byId = ref.read(personMapProvider);
    final Person? anchor = byId[anchorId];
    if (anchor == null) return;

    switch (_linkRelation) {
      case _LinkRelation.none:
        break;
      case _LinkRelation.child:
        await repo.linkChild(
          treeId: widget.treeId,
          parentId: anchor.id,
          childId: person.id,
        );
        for (final s in anchor.spouseIds) {
          await repo.linkChild(
            treeId: widget.treeId,
            parentId: s,
            childId: person.id,
          );
        }
        break;
      case _LinkRelation.parent:
        await repo.linkChild(
          treeId: widget.treeId,
          parentId: person.id,
          childId: anchor.id,
        );
        break;
      case _LinkRelation.spouse:
        await repo.linkSpouses(
          treeId: widget.treeId,
          aId: person.id,
          bId: anchor.id,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final List<Person> existingPeople =
        ref.watch(personsProvider).value ?? const <Person>[];
    final bool showLinking =
        widget.enableLinking && !_isEdit && existingPeople.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _isEdit
                    ? 'Edit person'
                    : (widget.relationLabel ?? 'Add person'),
                style: text.titleLarge,
              ),
              if (!_isEdit && widget.relativeOf != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '${_relationPreposition(widget.relationLabel)} ${widget.relativeOf}',
                  style: text.bodyMedium,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _given,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Given name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Given name is required.' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _surname,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Surname'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _otherNames,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Other names',
                  hintText: 'e.g. middle names',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nickname,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  hintText: 'e.g. Buddy',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _suffix,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Suffix',
                  hintText: 'e.g. Jr., III, PhD',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SexSelector(
                value: _sex,
                onChanged: (s) => setState(() => _sex = s),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _DateField(
                      label: 'Born',
                      date: _birthDate,
                      onTap: () => _pickDate(birth: true),
                      onClear: () => setState(() => _birthDate = null),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _DateField(
                      label: 'Died',
                      date: _deathDate,
                      onTap: () => _pickDate(birth: false),
                      onClear: () => setState(() => _deathDate = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _birthPlace,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Birthplace'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),
              if (showLinking) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                _LinkSection(
                  relation: _linkRelation,
                  anchorId: _anchorId,
                  people: existingPeople,
                  onRelationChanged: (r) {
                    setState(() {
                      _linkRelation = r;
                      // Default the anchor to the first person when a relation
                      // is first chosen.
                      if (r != _LinkRelation.none && _anchorId == null) {
                        _anchorId = existingPeople.first.id;
                      }
                    });
                  },
                  onAnchorChanged: (id) => setState(() => _anchorId = id),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(_isEdit ? 'Save changes' : 'Add person'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _SexSelector extends StatelessWidget {
  const _SexSelector({required this.value, required this.onChanged});
  final Sex value;
  final ValueChanged<Sex> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('SEX', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<Sex>(
          segments: const <ButtonSegment<Sex>>[
            ButtonSegment(value: Sex.male, label: Text('Male')),
            ButtonSegment(value: Sex.female, label: Text('Female')),
            ButtonSegment(value: Sex.unknown, label: Text('Unknown')),
          ],
          selected: <Sex>{value},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label.toUpperCase(), style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InputDecorator(
            decoration: InputDecoration(
              suffixIcon: date != null
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: onClear,
                    )
                  : const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(
              date != null ? Person.fmtDate(date!) : 'Year',
              style: date != null
                  ? text.bodyLarge
                  : text.bodyLarge?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ),
      ],
    );
  }
}

/// Optional "Add to tree" picker: choose how the new person relates to an
/// existing one, and which existing person.
class _LinkSection extends StatelessWidget {
  const _LinkSection({
    required this.relation,
    required this.anchorId,
    required this.people,
    required this.onRelationChanged,
    required this.onAnchorChanged,
  });

  final _LinkRelation relation;
  final String? anchorId;
  final List<Person> people;
  final ValueChanged<_LinkRelation> onRelationChanged;
  final ValueChanged<String?> onAnchorChanged;

  String _relationLabel(_LinkRelation r) {
    switch (r) {
      case _LinkRelation.none:
        return 'Not connected';
      case _LinkRelation.child:
        return 'Child of…';
      case _LinkRelation.parent:
        return 'Parent of…';
      case _LinkRelation.spouse:
        return 'Spouse of…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('ADD TO TREE', style: text.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<_LinkRelation>(
            initialValue: relation,
            decoration: const InputDecoration(labelText: 'Relationship'),
            items: _LinkRelation.values
                .map(
                  (r) => DropdownMenuItem<_LinkRelation>(
                    value: r,
                    child: Text(_relationLabel(r)),
                  ),
                )
                .toList(),
            onChanged: (r) {
              if (r != null) onRelationChanged(r);
            },
          ),
          if (relation != _LinkRelation.none) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: anchorId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Person'),
              items: people
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(
                        p.lifespan.isEmpty
                            ? p.fullName
                            : '${p.fullName} (${p.lifespan})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onAnchorChanged,
            ),
          ],
        ],
      ),
    );
  }
}

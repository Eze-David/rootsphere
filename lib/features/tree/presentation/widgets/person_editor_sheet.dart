import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/data/african_locations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/edit_history_entry.dart';
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
  Sex? defaultSex,
  bool enableLinking = false,
}) {
  return showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) => _PersonEditor(
      existing: existing,
      // Always fall back to the tree currently in view, never a hardcoded
      // demo tree — otherwise adding a person could spawn/populate a
      // different tree than the one the user is looking at.
      treeId: treeId ?? existing?.treeId ?? ref.read(activeTreeIdProvider),
      relationLabel: relationLabel,
      relativeOf: relativeOf,
      prefillSurname: prefillSurname,
      defaultSex: defaultSex,
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
    this.defaultSex,
    this.enableLinking = false,
  });
  final Person? existing;
  final String treeId;
  final String? relationLabel;
  final String? relativeOf;
  final String? prefillSurname;
  final Sex? defaultSex;
  final bool enableLinking;

  @override
  ConsumerState<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends ConsumerState<_PersonEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _prefix;
  late final TextEditingController _given;
  late final TextEditingController _surname;
  late final TextEditingController _otherNames;
  late final TextEditingController _nickname;
  late final TextEditingController _suffix;
  late final TextEditingController _birthPlace;
  late final TextEditingController _deathPlace;
  late String _birthCountry;
  late String _deathCountry;
  late final TextEditingController _religion;
  late final TextEditingController _education;
  late final TextEditingController _language;
  late final TextEditingController _occupation;
  late final TextEditingController _researchNotes;
  late final TextEditingController _researchQuestions;
  late final TextEditingController _city;
  late final TextEditingController _stateProvince;
  late final TextEditingController _region;
  late final TextEditingController _country;
  late final TextEditingController _notes;
  late Sex _sex;
  DateTime? _birthDate;
  DateTime? _deathDate;
  late bool _isDeceased;
  bool _saving = false;

  // Optional in-form linking (top-bar `+` flow).
  _LinkRelation _linkRelation = _LinkRelation.none;
  String? _anchorId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _prefix = TextEditingController(text: p?.prefix ?? '');
    _given = TextEditingController(text: p?.givenName ?? '');
    _surname = TextEditingController(
      text: p?.surname ?? widget.prefillSurname ?? '',
    );
    _otherNames = TextEditingController(text: p?.otherNames ?? '');
    _nickname = TextEditingController(text: p?.nickname ?? '');
    _suffix = TextEditingController(text: p?.suffix ?? '');
    _birthPlace = TextEditingController(text: p?.birthPlace ?? '');
    _deathPlace = TextEditingController(text: p?.deathPlace ?? '');
    _birthCountry = p?.birthPlace ?? '';
    _deathCountry = p?.deathPlace ?? '';
    _religion = TextEditingController(text: p?.religion ?? '');
    _education = TextEditingController(text: p?.education ?? '');
    _language = TextEditingController(text: p?.language ?? '');
    _occupation = TextEditingController(text: p?.occupation ?? '');
    _researchNotes = TextEditingController(text: p?.researchNotes ?? '');
    _researchQuestions = TextEditingController(
      text: p?.researchQuestions ?? '',
    );
    _city = TextEditingController(text: p?.city ?? '');
    _stateProvince = TextEditingController(text: p?.stateProvince ?? '');
    _region = TextEditingController(text: p?.region ?? '');
    _country = TextEditingController(text: p?.country ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _sex = p?.sex ?? widget.defaultSex ?? Sex.unknown;
    _birthDate = p?.birthDate;
    _deathDate = p?.deathDate;
    _isDeceased = p != null && !p.isLiving;
  }

  @override
  void dispose() {
    _prefix.dispose();
    _given.dispose();
    _surname.dispose();
    _otherNames.dispose();
    _nickname.dispose();
    _suffix.dispose();
    _birthPlace.dispose();
    _deathPlace.dispose();
    _religion.dispose();
    _education.dispose();
    _language.dispose();
    _occupation.dispose();
    _researchNotes.dispose();
    _researchQuestions.dispose();
    _city.dispose();
    _stateProvince.dispose();
    _region.dispose();
    _country.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool birth}) async {
    final DateTime initial =
        (birth ? _birthDate : _deathDate) ?? DateTime(1950);
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

    final repo = ref.read(treeRepositoryProvider);
    final String id =
        widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

    final Person person =
        (widget.existing ??
                Person(
                  id: id,
                  treeId: widget.treeId,
                  givenName: '',
                  code: Person.generateCode(),
                ))
            .copyWith(
              givenName: _given.text.trim(),
              surname: _surname.text.trim(),
              prefix: _prefix.text.trim().isEmpty ? null : _prefix.text.trim(),
              otherNames: _otherNames.text.trim().isEmpty
                  ? null
                  : _otherNames.text.trim(),
              nickname: _nickname.text.trim().isEmpty
                  ? null
                  : _nickname.text.trim(),
              suffix: _suffix.text.trim().isEmpty ? null : _suffix.text.trim(),
              sex: _sex,
              birthDate: _birthDate,
              deathDate: _deathDate,
              isDeceased: _isDeceased,
              birthPlace: _birthPlace.text.trim().isEmpty
                  ? null
                  : _birthPlace.text.trim(),
              deathPlace: _deathPlace.text.trim().isEmpty
                  ? null
                  : _deathPlace.text.trim(),
              religion: _religion.text.trim().isEmpty
                  ? null
                  : _religion.text.trim(),
              education: _education.text.trim().isEmpty
                  ? null
                  : _education.text.trim(),
              language: _language.text.trim().isEmpty
                  ? null
                  : _language.text.trim(),
              occupation: _occupation.text.trim().isEmpty
                  ? null
                  : _occupation.text.trim(),
              researchNotes: _researchNotes.text.trim().isEmpty
                  ? null
                  : _researchNotes.text.trim(),
              researchQuestions: _researchQuestions.text.trim().isEmpty
                  ? null
                  : _researchQuestions.text.trim(),
              city: _city.text.trim().isEmpty ? null : _city.text.trim(),
              stateProvince: _stateProvince.text.trim().isEmpty
                  ? null
                  : _stateProvince.text.trim(),
              region: _region.text.trim().isEmpty ? null : _region.text.trim(),
              country: _country.text.trim().isEmpty
                  ? null
                  : _country.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            );

    // Edits to an existing person require a documented reason. New people and
    // unchanged saves skip the prompt.
    String? reason;
    List<String> changed = const <String>[];
    if (_isEdit) {
      changed = _changedFields(widget.existing!, person);
      if (changed.isNotEmpty) {
        reason = await _promptEditReason(changed);
        if (reason == null) return; // Cancelled — keep the form open.
      }
    }

    setState(() => _saving = true);

    await repo.upsertPerson(person);
    await _applyLink(repo, person);

    // Force the tree to re-fetch so edits appear immediately, especially on
    // platforms where the realtime stream may not emit instantly.
    ref.invalidate(personsProvider);

    if (reason != null) {
      await repo.addEditHistory(
        EditHistoryEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          treeId: person.treeId,
          personId: person.id,
          reason: reason,
          editorName: _currentEditorName(),
          changedFields: changed,
          createdAt: DateTime.now(),
        ),
      );
    } else if (!_isEdit) {
      // No reason prompt for brand-new people, but still log the addition
      // (empty changedFields marks it as a creation, not an edit) so it shows
      // up in the dashboard's Recent Activity feed.
      await repo.addEditHistory(
        EditHistoryEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          treeId: person.treeId,
          personId: person.id,
          reason: 'Added to the tree',
          editorName: _currentEditorName(),
          createdAt: DateTime.now(),
        ),
      );
    }

    if (mounted) Navigator.pop(context, person);
  }

  /// Prefers the account's real name; an account that never got a
  /// `full_name` in its Supabase metadata falls back to the email's local
  /// part rather than showing the raw email address (matches the "Guest"
  /// vs. real-account naming convention in the profile screen's header).
  String? _currentEditorName() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final meta = user.userMetadata;
    final String? name =
        (meta?['full_name'] ?? meta?['name'] ?? meta?['display_name'])
            as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final String? email = user.email;
    if (email == null) return null;
    final int at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// Computes the human-readable labels of fields that differ between the
  /// previous and updated person.
  List<String> _changedFields(Person before, Person after) {
    final List<String> out = <String>[];
    void check(String label, Object? a, Object? b) {
      if (a != b) out.add(label);
    }

    check('Prefix', before.prefix, after.prefix);
    check('Given name', before.givenName, after.givenName);
    check('Surname', before.surname, after.surname);
    check('Other names', before.otherNames, after.otherNames);
    check('Nickname', before.nickname, after.nickname);
    check('Suffix', before.suffix, after.suffix);
    check('Sex', before.sex, after.sex);
    check('Birth date', before.birthDate, after.birthDate);
    check('Death date', before.deathDate, after.deathDate);
    check('Living status', before.isLiving, after.isLiving);
    check('Birthplace', before.birthPlace, after.birthPlace);
    check('Death place', before.deathPlace, after.deathPlace);
    check('Religion', before.religion, after.religion);
    check('Education', before.education, after.education);
    check('Language', before.language, after.language);
    check('Occupation', before.occupation, after.occupation);
    check('Research notes', before.researchNotes, after.researchNotes);
    check(
      'Research questions',
      before.researchQuestions,
      after.researchQuestions,
    );
    check('City', before.city, after.city);
    check('State / Province', before.stateProvince, after.stateProvince);
    check('Region', before.region, after.region);
    check('Country', before.country, after.country);
    check('Notes', before.notes, after.notes);
    return out;
  }

  /// Shows a required-reason dialog. Returns the trimmed reason, or null if the
  /// user cancelled.
  Future<String?> _promptEditReason(List<String> changed) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditReasonDialog(changedFields: changed),
    );
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
                controller: _prefix,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  hintText: 'e.g. Chief, Dr., Alhaji, Otunba',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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
              _LivingStatusSelector(
                isDeceased: _isDeceased,
                onChanged: (v) => setState(() => _isDeceased = v),
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
              _CountryDropdown(
                label: 'Birthplace',
                value: _birthCountry,
                onChanged: (v) => setState(() {
                  _birthCountry = v;
                  _birthPlace.text = v;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              _CountryDropdown(
                label: 'Death place',
                value: _deathCountry,
                onChanged: (v) => setState(() {
                  _deathCountry = v;
                  _deathPlace.text = v;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              _OtherAwareDropdown(
                label: 'Religion',
                options: religionOptions,
                value: _religion.text,
                onChanged: (v) => setState(() => _religion.text = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              _OtherAwareDropdown(
                label: 'Education',
                options: educationOptions,
                value: _education.text,
                onChanged: (v) => setState(() => _education.text = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              _OtherAwareDropdown(
                label: 'Language',
                options: languageOptions,
                value: _language.text,
                onChanged: (v) => setState(() => _language.text = v),
                customHint: 'e.g. Urhobo, Ijaw, Krio',
              ),
              const SizedBox(height: AppSpacing.lg),
              _OtherAwareDropdown(
                label: 'Occupation',
                options: occupationOptions,
                value: _occupation.text,
                onChanged: (v) => setState(() => _occupation.text = v),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('RESEARCH', style: text.labelSmall),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _researchNotes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Findings, sources, and notes',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _researchQuestions,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Open questions and next steps',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('LOCATION', style: text.labelSmall),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _SubdivisionDropdown(
                      country: _country.text,
                      value: _stateProvince.text,
                      onChanged: (v) => setState(() => _stateProvince.text = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _region,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Region'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _CountryDropdown(
                      label: 'Country',
                      value: _country.text,
                      onChanged: (v) => setState(() {
                        _country.text = v;
                        _stateProvince.clear();
                      }),
                    ),
                  ),
                ],
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

/// Explicit Living/Dead picker — independent of the Died year field, so
/// someone can be marked deceased without knowing exactly when.
class _LivingStatusSelector extends StatelessWidget {
  const _LivingStatusSelector({
    required this.isDeceased,
    required this.onChanged,
  });
  final bool isDeceased;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('LIVING STATUS', style: text.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment(value: false, label: Text('Living')),
            ButtonSegment(value: true, label: Text('Dead')),
          ],
          selected: <bool>{isDeceased},
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

const List<String> religionOptions = <String>[
  '',
  'Christianity',
  'Islam',
  'Traditional / Indigenous',
  'Hinduism',
  'Buddhism',
  'Judaism',
  'Atheist / Agnostic',
  'Other',
];

const List<String> educationOptions = <String>[
  '',
  'None',
  'Primary',
  'Secondary',
  'Vocational',
  'College / Diploma',
  'University / Degree',
  'Postgraduate',
  'Other',
];

const List<String> languageOptions = <String>[
  '',
  'Yoruba',
  'Igbo',
  'Hausa',
  'Tiv',
  'Fulfulde',
  'Kanuri',
  'Ibibio',
  'Edo',
  'Igala',
  'Nupe',
  'Efik',
  'Idoma',
  'Swahili',
  'Zulu',
  'Xhosa',
  'Afrikaans',
  'Sesotho',
  'Setswana',
  'Shona',
  'Ndebele',
  'Amharic',
  'Oromo',
  'Tigrinya',
  'Somali',
  'Kikuyu',
  'Luo',
  'Kinyarwanda',
  'Kirundi',
  'Chichewa',
  'Akan',
  'Twi',
  'Ga',
  'Ewe',
  'Fon',
  'Wolof',
  'Mandinka',
  'Bambara',
  'Lingala',
  'Kongo',
  'Tshiluba',
  'Dinka',
  'Malagasy',
  'Tamazight',
  'Arabic',
  'English',
  'French',
  'Portuguese',
  'Spanish',
  'Other',
];

const List<String> occupationOptions = <String>[
  '',
  'Farmer',
  'Trader / Merchant',
  'Teacher',
  'Doctor / Nurse',
  'Engineer',
  'Lawyer',
  'Soldier / Military',
  'Civil Servant',
  'Clergy / Religious Worker',
  'Artisan / Craftsman',
  'Domestic Worker',
  'Miner',
  'Railway Worker',
  'Seaman / Fisherman',
  'Student',
  'Unemployed',
  'Other',
];

/// A labeled dropdown whose options end in "Other" — picking it reveals a
/// text field for a free-text value instead of literally storing the word
/// "Other". Shared by religion/education/language/occupation, which only
/// differ in their label and option list.
class _OtherAwareDropdown extends StatefulWidget {
  const _OtherAwareDropdown({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.customHint,
  });

  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String? customHint;

  @override
  State<_OtherAwareDropdown> createState() => _OtherAwareDropdownState();
}

class _OtherAwareDropdownState extends State<_OtherAwareDropdown> {
  late final TextEditingController _custom;
  late bool _isCustom;

  bool _isKnownOption(String v) => v.isEmpty || widget.options.contains(v);

  @override
  void initState() {
    super.initState();
    // A previously-saved custom value (free text, not one of the presets)
    // means this field was filled in via "Other" — reopen the custom field
    // pre-filled rather than silently hiding it behind "Other".
    _isCustom = !_isKnownOption(widget.value);
    _custom = TextEditingController(text: _isCustom ? widget.value : '');
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String dropdownValue = _isCustom ? 'Other' : widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          value: dropdownValue.isEmpty ? null : dropdownValue,
          isExpanded: true,
          decoration: InputDecoration(labelText: widget.label),
          items: widget.options.map((String o) {
            return DropdownMenuItem<String>(
              value: o,
              child: Text(
                o.isEmpty ? '— Select ${widget.label.toLowerCase()} —' : o,
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v == 'Other') {
              setState(() => _isCustom = true);
              widget.onChanged(_custom.text.trim());
            } else {
              setState(() => _isCustom = false);
              widget.onChanged(v ?? '');
            }
          },
        ),
        if (_isCustom) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _custom,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Enter ${widget.label.toLowerCase()}',
              hintText: widget.customHint,
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ],
    );
  }
}

class _CountryDropdown extends StatelessWidget {
  const _CountryDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _countries = <String>['', ...africanCountries];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value.isEmpty ? null : value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: _countries.map((String c) {
        return DropdownMenuItem<String>(
          value: c,
          child: Text(c.isEmpty ? '— Select country —' : c),
        );
      }).toList(),
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _SubdivisionDropdown extends StatelessWidget {
  const _SubdivisionDropdown({
    required this.country,
    required this.value,
    required this.onChanged,
  });

  final String country;
  final String value;
  final ValueChanged<String> onChanged;

  static const Map<String, List<String>> _subdivisions = africanStatesProvinces;

  @override
  Widget build(BuildContext context) {
    final List<String> options = _subdivisions[country] ?? const <String>[];
    if (options.isEmpty) {
      return TextFormField(
        controller: TextEditingController(text: value),
        onChanged: onChanged,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'State / Province'),
      );
    }
    final List<String> items = <String>['', ...options];
    final bool valid = value.isEmpty || items.contains(value);
    return DropdownButtonFormField<String>(
      value: valid ? (value.isEmpty ? null : value) : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'State / Province'),
      items: items.map((String s) {
        return DropdownMenuItem<String>(
          value: s,
          child: Text(s.isEmpty ? '— Select state / province —' : s),
        );
      }).toList(),
      onChanged: (v) => onChanged(v ?? ''),
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

/// Required "reason for edit" dialog shown before an edit is saved. Returns the
/// trimmed reason via [Navigator.pop], or null when cancelled.
class _EditReasonDialog extends StatefulWidget {
  const _EditReasonDialog({required this.changedFields});
  final List<String> changedFields;

  @override
  State<_EditReasonDialog> createState() => _EditReasonDialogState();
}

class _EditReasonDialogState extends State<_EditReasonDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Reason for edit'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.changedFields.isEmpty
                  ? 'Briefly explain what you changed.'
                  : 'You changed: ${widget.changedFields.join(', ')}.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'e.g. Corrected birth year from her birth certificate',
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'A reason is required to save changes.'
                  : null,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/person.dart';
import '../../domain/entities/timeline_event.dart';
import '../providers/tree_providers.dart';

/// Bottom-sheet form to add or edit a custom [TimelineEvent] on [person].
///
/// Persists the change directly via the tree repository. Pass [existing] to
/// edit an event already on the person.
Future<void> showTimelineEventEditorSheet(
  BuildContext context,
  WidgetRef ref,
  Person person, {
  TimelineEvent? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _EventEditor(person: person, existing: existing),
  );
}

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({required this.person, this.existing});
  final Person person;
  final TimelineEvent? existing;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _place;
  late final TextEditingController _description;
  late LifeEventType _type;
  DateTime? _date;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _place = TextEditingController(text: e?.place ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _type = e?.type ?? LifeEventType.custom;
    _date = e?.date;
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(1980),
      firstDate: DateTime(1700),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final String id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final event = TimelineEvent(
      id: id,
      type: _type,
      title: _title.text.trim(),
      date: _date,
      place: _place.text.trim().isEmpty ? null : _place.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
    );

    final events = <TimelineEvent>[...widget.person.events];
    final idx = events.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      events[idx] = event;
    } else {
      events.add(event);
    }

    await ref
        .read(treeRepositoryProvider)
        .upsertPerson(widget.person.copyWith(events: events));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final events = widget.person.events
        .where((e) => e.id != widget.existing!.id)
        .toList();
    await ref
        .read(treeRepositoryProvider)
        .upsertPerson(widget.person.copyWith(events: events));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit event' : 'Add event',
                      style: text.titleLarge,
                    ),
                  ),
                  if (_isEdit)
                    IconButton(
                      tooltip: 'Delete event',
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error),
                      onPressed: _saving ? null : _delete,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('TYPE', style: text.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<LifeEventType>(
                initialValue: _type,
                items: LifeEventType.values
                    .map(
                      (t) => DropdownMenuItem<LifeEventType>(
                        value: t,
                        child: Text(_label(t)),
                      ),
                    )
                    .toList(),
                onChanged: (t) {
                  if (t != null) setState(() => _type = t);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Title is required.' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              _DateField(
                date: _date,
                onTap: _pickDate,
                onClear: () => setState(() => _date = null),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _place,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Place'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _description,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
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
                    : Text(_isEdit ? 'Save changes' : 'Add event'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  String _label(LifeEventType t) {
    final String n = t.name;
    return n[0].toUpperCase() + n.substring(1);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('DATE', style: text.labelSmall),
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
              date != null
                  ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                  : 'Pick a date',
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

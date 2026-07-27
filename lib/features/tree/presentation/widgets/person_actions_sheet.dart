import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/person.dart';
import '../providers/tree_providers.dart';
import 'person_editor_sheet.dart';

/// Shows the action menu for a tapped [person] (view profile, link relatives,
/// edit, delete).
Future<void> showPersonActionsSheet(
  BuildContext context,
  WidgetRef ref,
  Person person,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (sheetContext) => _ActionsList(person: person, ref: ref),
  );
}

class _ActionsList extends StatelessWidget {
  const _ActionsList({required this.person, required this.ref});
  final Person person;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    // Cap the sheet so it never exceeds the screen; the action list scrolls
    // on shorter devices instead of overflowing.
    final double maxHeight = MediaQuery.of(context).size.height * 0.8;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.cream,
                backgroundImage:
                    (person.photoUrl != null && person.photoUrl!.isNotEmpty)
                    ? NetworkImage(person.photoUrl!)
                    : null,
                child: (person.photoUrl != null && person.photoUrl!.isNotEmpty)
                    ? null
                    : const Icon(Icons.person, color: AppColors.primary),
              ),
              title: Text(person.fullName, style: text.titleMedium),
              subtitle: Text(person.lifespan.isEmpty ? '—' : person.lifespan),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Action(
                      icon: Icons.account_box_outlined,
                      label: 'View profile',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('${AppRoutes.person}/${person.id}');
                      },
                    ),
                    _Action(
                      icon: Icons.center_focus_strong_outlined,
                      label: 'Center on this person',
                      onTap: () {
                        setFocusPerson(ref, person.id);
                        Navigator.pop(context);
                      },
                    ),
                    _Action(
                      icon: Icons.child_care_outlined,
                      label: 'Add child',
                      onTap: () => _addRelative(context, PersonRelation.child),
                    ),
                    _Action(
                      icon: Icons.escalator_warning_outlined,
                      label: 'Add parent',
                      onTap: () =>
                          _addRelative(context, PersonRelation.parent),
                    ),
                    _Action(
                      icon: Icons.favorite_border,
                      label: 'Add spouse',
                      onTap: () =>
                          _addRelative(context, PersonRelation.spouse),
                    ),
                    if (person.parentIds.isNotEmpty)
                      _Action(
                        icon: Icons.people_outline,
                        label: 'Add sibling',
                        onTap: () =>
                            _addRelative(context, PersonRelation.sibling),
                      ),
                    _Action(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: () async {
                        Navigator.pop(context);
                        await showPersonEditorSheet(
                          context,
                          ref,
                          existing: person,
                        );
                      },
                    ),
                    _Action(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: AppColors.error,
                      onTap: () => _confirmDelete(context),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRelative(BuildContext context, PersonRelation relation) =>
      addNewRelative(context, ref, person, relation);

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${person.fullName}?'),
        content: const Text(
          'This removes the person and any relationship links to them. '
          'This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(treeRepositoryProvider)
          .deletePerson(person.treeId, person.id);
      // Clear focus if it pointed at the deleted person.
      if (ref.read(focusPersonIdProvider) == person.id) {
        ref.read(focusPersonIdProvider.notifier).state = null;
      }
      if (context.mounted) Navigator.pop(context);
    }
  }
}

enum PersonRelation { child, parent, spouse, sibling }

/// Creates a brand-new relative for [person] via the person editor sheet,
/// then links the created person as the given [relation]. Shared by the
/// tree node's "Add child/parent/spouse/sibling" actions and the profile
/// screen's "Add family member" shortcut.
Future<void> addNewRelative(
  BuildContext context,
  WidgetRef ref,
  Person person,
  PersonRelation relation,
) async {
  final Person? created = await showPersonEditorSheet(
    context,
    ref,
    treeId: person.treeId,
    relationLabel: switch (relation) {
      PersonRelation.child => 'Add child',
      PersonRelation.parent => 'Add parent',
      PersonRelation.spouse => 'Add spouse',
      PersonRelation.sibling => 'Add sibling',
    },
    relativeOf: person.fullName,
    // Children and siblings commonly share the parent's surname; pre-fill
    // as a convenience.
    prefillSurname:
        relation == PersonRelation.child || relation == PersonRelation.sibling
        ? person.surname
        : null,
  );
  if (created == null) return;
  await linkExistingRelative(ref, person, created.id, relation);
}

/// Links an already-existing person as [relation] of [person] — used both
/// right after creating a brand-new relative above, and when linking a
/// person found via search instead of creating a duplicate record.
///
/// Siblings aren't a stored relationship in their own right — they're
/// derived from sharing a parent — so linking as a sibling attaches
/// [relativeId] as another child of every one of [person]'s recorded
/// parents. If [person] has no parent recorded yet, there's nothing to
/// attach to and this is a no-op (the UI hides "Add sibling" in that case).
Future<void> linkExistingRelative(
  WidgetRef ref,
  Person person,
  String relativeId,
  PersonRelation relation,
) async {
  final repo = ref.read(treeRepositoryProvider);
  switch (relation) {
    case PersonRelation.child:
      await repo.linkChild(
        treeId: person.treeId,
        parentId: person.id,
        childId: relativeId,
      );
      // Also link the spouse as a parent if present.
      for (final s in person.spouseIds) {
        await repo.linkChild(
          treeId: person.treeId,
          parentId: s,
          childId: relativeId,
        );
      }
      break;
    case PersonRelation.parent:
      await repo.linkChild(
        treeId: person.treeId,
        parentId: relativeId,
        childId: person.id,
      );
      break;
    case PersonRelation.spouse:
      await repo.linkSpouses(
        treeId: person.treeId,
        aId: person.id,
        bId: relativeId,
      );
      break;
    case PersonRelation.sibling:
      for (final parentId in person.parentIds) {
        await repo.linkChild(
          treeId: person.treeId,
          parentId: parentId,
          childId: relativeId,
        );
      }
      break;
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary),
      title: Text(label, style: text.bodyLarge?.copyWith(color: color)),
      onTap: onTap,
    );
  }
}

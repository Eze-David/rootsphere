import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/screens/legal_document_screen.dart';
import '../../../collab/presentation/screens/my_donations_screen.dart';
import '../../../collab/presentation/providers/role_verification_providers.dart';
import '../../../tree/presentation/providers/tree_providers.dart';
import '../../domain/entities/family_tree.dart';
import '../providers/family_tree_provider.dart';
import '../providers/settings_provider.dart';

/// Full profile screen with family-tree linking, account management,
/// settings, and sign-out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(authStateProvider).value;
    final bool authLoading = ref.watch(authControllerProvider).isLoading;

    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next.hasError) {
        final Object error = next.error!;
        _showSnack(
          context,
          error is Failure ? error.message : 'Something went wrong.',
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          _UserHeader(user: user),
          const SizedBox(height: AppSpacing.xl),
          _FamilyTreeSection(),
          const SizedBox(height: AppSpacing.xl),
          _AccountSection(),
          const SizedBox(height: AppSpacing.xl),
          _SettingsSection(),
          const SizedBox(height: AppSpacing.xl),
          _SupportSection(),
          const SizedBox(height: AppSpacing.xl),
          _SignOutButton(loading: authLoading),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User header
// ─────────────────────────────────────────────────────────────────────────────

class _UserHeader extends StatelessWidget {
  const _UserHeader({this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.cream,
              backgroundImage: user?.avatarUrl != null
                  ? NetworkImage(user!.avatarUrl!)
                  : null,
              child: user?.avatarUrl == null
                  ? const Icon(Icons.person, size: 28, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user?.displayName ?? 'Guest',
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? 'Not signed in',
                    style: text.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Family tree linking
// ─────────────────────────────────────────────────────────────────────────────

class _FamilyTreeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<FamilyTree>> treesAsync = ref.watch(
      familyTreeControllerProvider,
    );
    final String activeTreeId = ref.watch(activeTreeIdProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('FAMILY TREES', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            treesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                error is Failure
                    ? error.message
                    : 'Could not load your family trees.',
                style: text.bodyMedium?.copyWith(color: AppColors.error),
              ),
              data: (trees) {
                if (trees.isEmpty) {
                  return Text(
                    'You are not linked to any family trees yet.',
                    style: text.bodyMedium,
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final tree in trees)
                      _TreeListTile(
                        tree: tree,
                        selected: tree.id == activeTreeId,
                        onSelect: () => _selectTree(context, ref, tree),
                        onCopyId: () => _copyTreeId(context, tree),
                        onRename: tree.role == TreeRole.owner
                            ? () => _showRenameTreeDialog(context, ref, tree)
                            : null,
                        onUnlink: () => _unlinkTree(context, ref, tree),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showCreateTreeDialog(context, ref),
                    child: const Text('Create tree'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showJoinTreeDialog(context, ref),
                    child: const Text('Join tree'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Copies a tree's id to the clipboard so it can be shared with others to
  /// join. Shows a confirmation snackbar.
  Future<void> _copyTreeId(BuildContext context, FamilyTree tree) async {
    await Clipboard.setData(ClipboardData(text: tree.id));
    if (context.mounted) {
      _snack(context, 'Tree ID copied — share it so others can join.');
    }
  }

  /// Sets [tree] as the active tree and jumps to the Tree tab.
  void _selectTree(BuildContext context, WidgetRef ref, FamilyTree tree) {
    setSelectedTreeId(ref, tree.id);
    ref.read(focusPersonIdProvider.notifier).state = null;
    _snack(context, 'Now viewing "${tree.name}".');
    context.go(AppRoutes.tree);
  }

  Future<void> _unlinkTree(
    BuildContext context,
    WidgetRef ref,
    FamilyTree tree,
  ) async {
    final bool wasActive = ref.read(activeTreeIdProvider) == tree.id;
    try {
      await ref.read(familyTreeControllerProvider.notifier).unlinkTree(tree.id);
      if (wasActive) {
        setSelectedTreeId(ref, null);
      }
    } catch (e) {
      if (context.mounted) _snack(context, _messageFor(e));
    }
  }

  void _showRenameTreeDialog(
    BuildContext context,
    WidgetRef ref,
    FamilyTree tree,
  ) {
    final controller = TextEditingController(text: tree.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename family tree'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Tree name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref
                    .read(familyTreeControllerProvider.notifier)
                    .renameTree(tree.id, name);
                if (context.mounted) {
                  _snack(context, 'Tree renamed to "$name".');
                }
              } catch (e) {
                if (context.mounted) _snack(context, _messageFor(e));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCreateTreeDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Create family tree'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Tree name'),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                try {
                  final tree = await ref
                      .read(familyTreeControllerProvider.notifier)
                      .createTree(name);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text('Tree "$name" created.'),
                          action: SnackBarAction(
                            label: 'Copy ID',
                            onPressed: () => _copyTreeId(context, tree),
                          ),
                        ),
                      );
                  }
                } catch (e) {
                  if (context.mounted) _snack(context, _messageFor(e));
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showJoinTreeDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _JoinTreeDialog(parentContext: context),
    );
  }
}

/// Stateful join dialog so it can show inline validation, a busy state, and
/// surface errors (e.g. an unknown tree id) without closing prematurely.
class _JoinTreeDialog extends ConsumerStatefulWidget {
  const _JoinTreeDialog({required this.parentContext});

  /// The screen context, used to show a snackbar after the dialog closes.
  final BuildContext parentContext;

  @override
  ConsumerState<_JoinTreeDialog> createState() => _JoinTreeDialogState();
}

class _JoinTreeDialogState extends ConsumerState<_JoinTreeDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Enter a tree ID.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tree = await ref
          .read(familyTreeControllerProvider.notifier)
          .joinTree(id, fallbackName: _nameController.text.trim());
      if (mounted) Navigator.pop(context);
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Joined "${tree.name}".')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is Failure ? e.message : 'Could not join that tree.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join family tree'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _idController,
            enabled: !_busy,
            autofocus: true,
            decoration: InputDecoration(hintText: 'Tree ID', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'Tree name (optional)'),
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}

String _messageFor(Object error) =>
    error is Failure ? error.message : 'Something went wrong.';

class _TreeListTile extends StatelessWidget {
  const _TreeListTile({
    required this.tree,
    required this.selected,
    required this.onSelect,
    required this.onCopyId,
    this.onRename,
    required this.onUnlink,
  });
  final FamilyTree tree;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onCopyId;
  final VoidCallback? onRename;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onSelect,
      leading: Icon(
        selected ? Icons.park : Icons.park_outlined,
        color: AppColors.primary,
      ),
      title: Text(tree.name, style: text.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${tree.role.name[0].toUpperCase()}${tree.role.name.substring(1)} · '
            '${tree.memberCount} member${tree.memberCount == 1 ? '' : 's'}'
            '${selected ? ' · Active' : ''}',
            style: text.bodySmall,
          ),
          const SizedBox(height: 2),
          // Tappable ID row so it's obvious this is the value to share/join with.
          InkWell(
            onTap: onCopyId,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    'ID: ${tree.id}',
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.copy, size: 13, color: AppColors.textTertiary),
              ],
            ),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (value) {
          if (value == 'copy') onCopyId();
          if (value == 'rename') onRename?.call();
          if (value == 'unlink') onUnlink();
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'copy',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.copy, size: 20),
              title: Text('Copy tree ID'),
            ),
          ),
          if (onRename != null)
            const PopupMenuItem<String>(
              value: 'rename',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit, size: 20),
                title: Text('Rename'),
              ),
            ),
          const PopupMenuItem<String>(
            value: 'unlink',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.link_off, size: 20),
              title: Text('Unlink'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account management
// ─────────────────────────────────────────────────────────────────────────────

class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppUser? user = ref.watch(authStateProvider).value;
    final bool loading = ref.watch(authControllerProvider).isLoading;
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('ACCOUNT', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            if (isAdmin) ...<Widget>[
              _AccountTile(
                icon: Icons.fact_check_outlined,
                label: 'Review applications',
                onTap: () => context.push(AppRoutes.roleVerificationReview),
              ),
              _AccountTile(
                icon: Icons.apartment_outlined,
                label: 'Company requests',
                onTap: () => context.push(AppRoutes.companyRequests),
              ),
              _AccountTile(
                icon: Icons.rate_review_outlined,
                label: 'Review submissions',
                onTap: () => context.push(AppRoutes.submissionReview),
              ),
            ],
            _AccountTile(
              icon: Icons.lock_outline,
              label: 'Change password',
              onTap: loading
                  ? null
                  : () => _showChangePasswordDialog(context, ref),
            ),
            _AccountTile(
              icon: Icons.mark_email_unread_outlined,
              label: 'Resend verification email',
              onTap: loading || user == null
                  ? null
                  : () => _resendVerification(context, ref, user.email),
            ),
            _AccountTile(
              icon: Icons.delete_outline,
              label: 'Delete account',
              labelColor: AppColors.error,
              onTap: loading
                  ? null
                  : () => _showDeleteAccountDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resendVerification(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .resendEmailConfirmation(email);
    if (context.mounted && ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification email sent.')));
    }
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final formKey = GlobalKey<FormState>();
    final passController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Change password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) {
                    if ((v ?? '').length < 8)
                      return 'Use at least 8 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  validator: (v) {
                    if (v != passController.text)
                      return 'Passwords do not match.';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final ok = await ref
                    .read(authControllerProvider.notifier)
                    .updatePassword(passController.text);
                if (ctx.mounted && ok) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated.')),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'This will permanently remove your account and all linked data. '
            'This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await ref
                    .read(authControllerProvider.notifier)
                    .deleteAccount();
                if (context.mounted && ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Account deletion requested. You may be signed out.',
                      ),
                    ),
                  );
                }
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.label,
    this.labelColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: labelColor ?? AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: text.bodyLarge?.copyWith(color: labelColor),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsControllerProvider);
    final settingsNotifier = ref.read(settingsControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('SETTINGS', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            _SettingsTile(
              icon: Icons.dark_mode_outlined,
              label: 'Theme',
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  isDense: true,
                  icon: const Icon(Icons.expand_more, size: 20),
                  items: ThemeMode.values.map((mode) {
                    return DropdownMenuItem<ThemeMode>(
                      value: mode,
                      child: Text(
                        mode.name[0].toUpperCase() + mode.name.substring(1),
                        style: text.bodyMedium,
                      ),
                    );
                  }).toList(),
                  onChanged: (mode) {
                    if (mode != null) settingsNotifier.setThemeMode(mode);
                  },
                ),
              ),
            ),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              trailing: Switch(
                value: settings.notificationsEnabled,
                onChanged: (v) => settingsNotifier.setNotifications(v),
              ),
            ),
            _SettingsTile(
              icon: Icons.language_outlined,
              label: 'Language',
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: settings.languageCode,
                  isDense: true,
                  icon: const Icon(Icons.expand_more, size: 20),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                  ],
                  onChanged: (code) {
                    if (code != null) settingsNotifier.setLanguage(code);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: text.bodyLarge)),
          trailing,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Support
// ─────────────────────────────────────────────────────────────────────────────

class _SupportSection extends StatelessWidget {
  static const String _supportEmail = 'Vdst2009@gmail.com';

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('SUPPORT', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            _AccountTile(
              icon: Icons.mail_outline,
              label: 'Contact us',
              onTap: () => _showContactUsDialog(context),
            ),
            _AccountTile(
              icon: Icons.info_outline,
              label: 'About us',
              onTap: () => _showAboutUsDialog(context),
            ),
            _AccountTile(
              icon: Icons.volunteer_activism_outlined,
              label: 'Donations',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyDonationsScreen(),
                ),
              ),
            ),
            _AccountTile(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalDocumentScreen.termsOfService(),
                ),
              ),
            ),
            _AccountTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalDocumentScreen.privacyPolicy(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactUsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Contact us'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Have a question or found an issue? Reach out and we\'ll get '
                'back to you.',
              ),
              const SizedBox(height: AppSpacing.lg),
              InkWell(
                onTap: () => _emailUs(ctx),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.email_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Text(_supportEmail),
                    ],
                  ),
                ),
              ),
              // Address and phone number are coming soon — kept as their own
              // rows above so they slot in the same way once available.
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _emailUs(BuildContext context) async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('Rootsphere support')}',
    );
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your email app.')),
      );
    }
  }

  void _showAboutUsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('About us'),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Rootsphere',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Discover, document and grow your family history.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                SizedBox(height: AppSpacing.lg),
                Text(
                  'Rootsphere is a family history app built around African '
                  'ancestry research. Build an interactive family tree across '
                  'ancestors, descendants, and pedigree views; collect birth, '
                  'marriage, death, baptism, census, and other records in one '
                  'place with OCR and an AI research assistant; and '
                  'collaborate with the community to find, index, and verify '
                  'records for opportunities near you.',
                ),
                SizedBox(height: AppSpacing.lg),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign out
// ─────────────────────────────────────────────────────────────────────────────

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: loading
            ? null
            : () {
                // Ask for confirmation
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign out?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          // ConsumerWidget ancestor reads ref via Builder
                          final container = ProviderScope.containerOf(context);
                          container
                              .read(authControllerProvider.notifier)
                              .signOut();
                        },
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
              },
        child: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign out'),
      ),
    );
  }
}

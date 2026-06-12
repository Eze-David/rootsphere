import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
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
              backgroundImage:
                  user?.avatarUrl != null
                      ? NetworkImage(user!.avatarUrl!)
                      : null,
              child:
                  user?.avatarUrl == null
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
    final List<FamilyTree> trees = ref.watch(familyTreeControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('FAMILY TREES', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            if (trees.isEmpty)
              Text(
                'You are not linked to any family trees yet.',
                style: text.bodyMedium,
              )
            else
              Column(
                children: <Widget>[
                  for (final tree in trees)
                    _TreeListTile(
                      tree: tree,
                      onUnlink: () async {
                        await ref
                            .read(familyTreeControllerProvider.notifier)
                            .unlinkTree(tree.id);
                      },
                    ),
                ],
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
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await ref
                      .read(familyTreeControllerProvider.notifier)
                      .createTree(name);
                  if (context.mounted) Navigator.pop(ctx);
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
    final idController = TextEditingController();
    final nameController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Join family tree'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: idController,
                decoration: const InputDecoration(hintText: 'Tree ID'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'Tree name (optional)'),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final id = idController.text.trim();
                if (id.isNotEmpty) {
                  await ref
                      .read(familyTreeControllerProvider.notifier)
                      .joinTree(id, nameController.text.trim());
                  if (context.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }
}

class _TreeListTile extends StatelessWidget {
  const _TreeListTile({required this.tree, required this.onUnlink});
  final FamilyTree tree;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.park_outlined, color: AppColors.primary),
      title: Text(tree.name, style: text.titleMedium),
      subtitle: Text(
        '${tree.role.name[0].toUpperCase()}${tree.role.name.substring(1)} · ${tree.memberCount} members',
        style: text.bodySmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.link_off, size: 20),
        onPressed: onUnlink,
        tooltip: 'Unlink',
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('ACCOUNT', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            _AccountTile(
              icon: Icons.lock_outline,
              label: 'Change password',
              onTap: loading ? null : () => _showChangePasswordDialog(context, ref),
            ),
            _AccountTile(
              icon: Icons.mark_email_unread_outlined,
              label: 'Resend verification email',
              onTap:
                  loading || user == null
                      ? null
                      : () => _resendVerification(context, ref, user.email),
            ),
            _AccountTile(
              icon: Icons.delete_outline,
              label: 'Delete account',
              labelColor: AppColors.error,
              onTap: loading ? null : () => _showDeleteAccountDialog(context, ref),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent.')),
      );
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
                    if ((v ?? '').length < 8) return 'Use at least 8 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) {
                    if (v != passController.text) return 'Passwords do not match.';
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
              child: const Text('Delete', style: TextStyle(color: AppColors.error)),
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
        onPressed:
            loading
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
        child:
            loading
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

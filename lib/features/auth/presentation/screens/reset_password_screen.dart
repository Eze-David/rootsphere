import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/auth_controller.dart';

/// Landed on via the password-reset email link (see docs/auth-email-links.md
/// and [passwordRecoveryProvider], which the router uses to force navigation
/// here). The temporary recovery session is only good for setting a new
/// password — once that succeeds we navigate to [AppRoutes.home] ourselves;
/// the router's redirect guard only *blocks* leaving this screen while
/// [passwordRecoveryProvider] is true, it doesn't push a new destination once
/// that flips false, so nothing else would ever move the user off this
/// screen.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    final ok = await controller.updatePassword(_passwordController.text);
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<void> state = ref.watch(authControllerProvider);
    final bool loading = state.isLoading;

    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next.hasError) {
        final Object error = next.error!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                error is Failure ? error.message : 'Something went wrong.',
              ),
            ),
          );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Set a new password', style: text.displayMedium),
                    AppSpacing.gapMd,
                    Text(
                      'Choose a new password for your Rootsphere account.',
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    AppTextField(
                      label: 'New password',
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v ?? '').length < 8
                          ? 'Use at least 8 characters.'
                          : null,
                    ),
                    AppSpacing.gapLg,
                    AppTextField(
                      label: 'Confirm password',
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      controller: _confirmController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      validator: (v) => v != _passwordController.text
                          ? 'Passwords do not match.'
                          : null,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              )
                            : const Text('Update password'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

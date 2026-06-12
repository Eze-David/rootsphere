import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/oauth_button.dart';
import '../providers/auth_controller.dart';

/// Combined sign-up / sign-in screen (brief §5.1, mockup "SIGN UP / LOGIN").
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSignUp = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final ok = _isSignUp
        ? await controller.signUp(email, password)
        : await controller.signIn(email, password);
    if (ok && mounted && _isSignUp) {
      _showSnack('Account created. Check your email to confirm.');
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('Enter your email first, then tap reset.');
      return;
    }
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(email);
    if (ok && mounted) _showSnack('Password reset link sent to $email.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<void> state = ref.watch(authControllerProvider);
    final bool loading = state.isLoading;

    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next.hasError) {
        final Object error = next.error!;
        _showSnack(error is Failure ? error.message : 'Something went wrong.');
      }
    });

    return Scaffold(
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
                  children: <Widget>[
                    _Logo(),
                    AppSpacing.gapLg,
                    Text(
                      'Discover, document and grow\nyour family history',
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    AppTextField(
                      label: 'Email',
                      hint: 'you@example.com',
                      icon: Icons.mail_outline,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateEmail,
                    ),
                    AppSpacing.gapLg,
                    AppTextField(
                      label: 'Password',
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction:
                          _isSignUp ? TextInputAction.next : TextInputAction.done,
                      validator: _validatePassword,
                      onSubmitted: (_) {
                        if (!_isSignUp) _submit();
                      },
                    ),
                    if (_isSignUp) ...<Widget>[
                      AppSpacing.gapLg,
                      AppTextField(
                        label: 'Confirm password',
                        hint: '••••••••',
                        icon: Icons.lock_outline,
                        controller: _confirmPasswordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        validator: _validateConfirmPassword,
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (!_isSignUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: loading ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton(
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
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _DividerLabel(label: 'or continue with'),
                    const SizedBox(height: AppSpacing.lg),
                    OAuthButton(
                      label: 'Google',
                      icon: Icons.g_mobiledata,
                      enabled: !loading,
                      onPressed: () => ref
                          .read(authControllerProvider.notifier)
                          .signInWithGoogle(),
                    ),
                    AppSpacing.gapMd,
                    OAuthButton(
                      label: 'Apple',
                      icon: Icons.apple,
                      enabled: !loading,
                      onPressed: () => ref
                          .read(authControllerProvider.notifier)
                          .signInWithApple(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _ToggleAuthMode(
                      isSignUp: _isSignUp,
                      onToggle: loading
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
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

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      return 'Enter a valid email.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Password is required.';
    if ((value ?? '').length < 8) return 'Use at least 8 characters.';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (_isSignUp && (value ?? '').isEmpty) return 'Confirm your password.';
    if (_isSignUp && value != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: 140,
      fit: BoxFit.contain,
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}

class _ToggleAuthMode extends StatelessWidget {
  const _ToggleAuthMode({required this.isSignUp, required this.onToggle});
  final bool isSignUp;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          isSignUp ? 'Already have an account? ' : "Don't have an account? ",
          style: text.bodyMedium,
        ),
        GestureDetector(
          onTap: onToggle,
          child: Text(
            isSignUp ? 'Sign in' : 'Sign up',
            style: text.labelLarge?.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

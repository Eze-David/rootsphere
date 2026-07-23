import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/oauth_button.dart';
import '../providers/auth_controller.dart';
import 'legal_document_screen.dart';

/// Combined sign-up / sign-in screen (brief §5.1, mockup "SIGN UP / LOGIN").
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSignUp = true;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUp && !_agreedToTerms) {
      _showSnack('Please agree to the Terms of Service and Privacy Policy.');
      return;
    }
    final controller = ref.read(authControllerProvider.notifier);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    // The rest of the app (opportunity requester/claimer names, edit
    // history, etc.) reads a single `full_name` from user metadata — joining
    // here keeps that everywhere-else convention intact while letting the
    // form collect first/last separately.
    final String fullName = <String>[
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    final ok = _isSignUp
        ? await controller.signUp(fullName, email, password)
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

  /// Google/Apple also create an account on first use, so they're gated by
  /// the same agreement as email/password sign-up — but rather than a
  /// mysteriously-disabled button, tapping while unchecked explains why.
  void _oauth(VoidCallback signIn) {
    if (_isSignUp && !_agreedToTerms) {
      _showSnack('Please agree to the Terms of Service and Privacy Policy.');
      return;
    }
    signIn();
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
    final bool blockedBySignUpAgreement = _isSignUp && !_agreedToTerms;

    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next.hasError) {
        final Object error = next.error!;
        _showSnack(error is Failure ? error.message : 'Something went wrong.');
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              'assets/images/onboarding -image.png',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 96,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusXl,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'Discover, document and grow\nyour family history',
                                    textAlign: TextAlign.center,
                                    style: text.bodyLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxl),
                                  if (_isSignUp) ...<Widget>[
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Expanded(
                                          child: AppTextField(
                                            label: 'First name',
                                            hint: 'e.g. Adaeze',
                                            icon: Icons.person_outline,
                                            controller: _firstNameController,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            textInputAction:
                                                TextInputAction.next,
                                            validator: _validateFirstName,
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.md),
                                        Expanded(
                                          child: AppTextField(
                                            label: 'Last name',
                                            hint: 'e.g. Okonkwo',
                                            icon: Icons.person_outline,
                                            controller: _lastNameController,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            textInputAction:
                                                TextInputAction.next,
                                            validator: _validateLastName,
                                          ),
                                        ),
                                      ],
                                    ),
                                    AppSpacing.gapLg,
                                  ],
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
                                    textInputAction: _isSignUp
                                        ? TextInputAction.next
                                        : TextInputAction.done,
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
                                    const SizedBox(height: AppSpacing.md),
                                    _TermsAgreement(
                                      value: _agreedToTerms,
                                      onChanged: loading
                                          ? null
                                          : (v) => setState(
                                              () => _agreedToTerms = v,
                                            ),
                                    ),
                                  ],
                                  if (!_isSignUp)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: loading
                                            ? null
                                            : _resetPassword,
                                        child: const Text('Forgot password?'),
                                      ),
                                    ),
                                  const SizedBox(height: AppSpacing.lg),
                                  ElevatedButton(
                                    onPressed:
                                        loading || blockedBySignUpAgreement
                                        ? null
                                        : _submit,
                                    child: loading
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.onPrimary,
                                            ),
                                          )
                                        : Text(
                                            _isSignUp
                                                ? 'Create account'
                                                : 'Sign in',
                                          ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  _DividerLabel(label: 'or continue with'),
                                  const SizedBox(height: AppSpacing.lg),
                                  OAuthButton(
                                    label: 'Google',
                                    icon: Icons.g_mobiledata,
                                    enabled: !loading,
                                    onPressed: () => _oauth(
                                      () => ref
                                          .read(authControllerProvider.notifier)
                                          .signInWithGoogle(),
                                    ),
                                  ),
                                  AppSpacing.gapMd,
                                  OAuthButton(
                                    label: 'Apple',
                                    icon: Icons.apple,
                                    enabled: !loading,
                                    onPressed: () => _oauth(
                                      () => ref
                                          .read(authControllerProvider.notifier)
                                          .signInWithApple(),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  _ToggleAuthMode(
                                    isSignUp: _isSignUp,
                                    onToggle: loading
                                        ? null
                                        : () => setState(
                                            () => _isSignUp = !_isSignUp,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateFirstName(String? value) {
    if (!_isSignUp) return null;
    if ((value?.trim() ?? '').isEmpty) return 'First name is required.';
    return null;
  }

  String? _validateLastName(String? value) {
    if (!_isSignUp) return null;
    if ((value?.trim() ?? '').isEmpty) return 'Last name is required.';
    return null;
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

/// Required-before-sign-up agreement checkbox with tappable links to the full
/// Terms of Service / Privacy Policy — the standard pattern most apps use
/// ahead of account creation.
class _TermsAgreement extends StatelessWidget {
  const _TermsAgreement({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? linkStyle = text.bodyMedium?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Checkbox(
          value: value,
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RichText(
              text: TextSpan(
                style: text.bodyMedium,
                children: <InlineSpan>[
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(
                        context,
                        const LegalDocumentScreen.termsOfService(),
                      ),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(
                        context,
                        const LegalDocumentScreen.privacyPolicy(),
                      ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/oauth_button.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_mode_provider.dart';
import 'legal_document_screen.dart';

/// Combined sign-up / sign-in screen: a dark gradient header (brand espresso
/// colour) behind a floating rounded card with underline-style fields.
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
  void initState() {
    super.initState();
    // Set once from whichever entry point sent the user here (the landing
    // page's "Get started" vs "Sign in" buttons) — read via ref.read since
    // this is a one-time initial value, not something this screen should
    // keep reacting to afterwards.
    _isSignUp = ref.read(authInitialModeProvider);
  }

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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AsyncValue<void> state = ref.watch(authControllerProvider);
    final bool loading = state.isLoading;
    final bool blockedBySignUpAgreement = _isSignUp && !_agreedToTerms;

    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next.hasError) {
        final Object error = next.error!;
        _showSnack(error is Failure ? error.message : 'Something went wrong.');
      }
    });

    final Color headerTop = Color.lerp(scheme.primary, Colors.white, 0.12)!;
    final Color headerBottom = Color.lerp(scheme.primary, Colors.black, 0.55)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[headerTop, headerBottom],
                ),
              ),
            ),
            Positioned(
              top: -40,
              right: -30,
              child: _DecorativeCircle(
                diameter: 140,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Positioned(
              top: 160,
              left: -50,
              child: _DecorativeCircle(
                diameter: 110,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => context.go(AppRoutes.onboarding),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isSignUp ? 'Create Your\nAccount' : 'Welcome\nBack',
                        style: text.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
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
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusXl + 8,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 32,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (_isSignUp) ...<Widget>[
                                    _AuthField(
                                      label: 'First Name',
                                      hint: 'e.g. John',
                                      controller: _firstNameController,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      textInputAction: TextInputAction.next,
                                      validator: _validateFirstName,
                                    ),
                                    AppSpacing.gapLg,
                                    _AuthField(
                                      label: 'Last Name',
                                      hint: 'e.g. Smith',
                                      controller: _lastNameController,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      textInputAction: TextInputAction.next,
                                      validator: _validateLastName,
                                    ),
                                    AppSpacing.gapLg,
                                  ],
                                  _AuthField(
                                    label: 'Email',
                                    hint: 'you@example.com',
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    validator: _validateEmail,
                                  ),
                                  AppSpacing.gapLg,
                                  _AuthField(
                                    label: 'Password',
                                    hint: '••••••••',
                                    controller: _passwordController,
                                    isPassword: true,
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
                                    _AuthField(
                                      label: 'Confirm Password',
                                      hint: '••••••••',
                                      controller: _confirmPasswordController,
                                      isPassword: true,
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
                                  const SizedBox(height: AppSpacing.xl),
                                  _GradientSubmitButton(
                                    label: _isSignUp ? 'SIGN UP' : 'SIGN IN',
                                    loading: loading,
                                    onPressed:
                                        loading || blockedBySignUpAgreement
                                        ? null
                                        : _submit,
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

/// Soft translucent circle used to decorate the header, matching the
/// mockup's overflowing background shapes.
class _DecorativeCircle extends StatelessWidget {
  const _DecorativeCircle({required this.diameter, required this.color});
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Labelled underline field matching the new auth mockup: a bold brand-
/// coloured caption above an underlined input, with a trailing checkmark
/// once the value is valid (or a show/hide toggle for password fields).
class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.label,
    required this.hint,
    required this.controller,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color dividerColor = Theme.of(context).dividerColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: text.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final bool showCheck =
                !widget.isPassword &&
                value.text.isNotEmpty &&
                (widget.validator == null ||
                    widget.validator!(value.text) == null);
            return TextFormField(
              controller: widget.controller,
              obscureText: widget.isPassword && _obscured,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              validator: widget.validator,
              onFieldSubmitted: widget.onSubmitted,
              style: text.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: dividerColor),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: dividerColor),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: scheme.primary, width: 1.5),
                ),
                errorBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: scheme.error),
                ),
                focusedErrorBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: scheme.error, width: 1.5),
                ),
                suffixIcon: widget.isPassword
                    ? IconButton(
                        icon: Icon(
                          _obscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: text.bodyMedium?.color,
                        ),
                        onPressed: () =>
                            setState(() => _obscured = !_obscured),
                      )
                    : (showCheck
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 20,
                            )
                          : null),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Full-width gradient pill button (brand espresso colour) used for the
/// primary sign up / sign in action, matching the mockup's pill CTA.
class _GradientSubmitButton extends StatelessWidget {
  const _GradientSubmitButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Ink(
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color.lerp(scheme.primary, Colors.white, 0.15)!,
                  Color.lerp(scheme.primary, Colors.black, 0.35)!,
                ],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
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
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
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
      color: text.bodyLarge?.color,
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
    final Color dividerColor = Theme.of(context).dividerColor;
    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: dividerColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: Divider(color: dividerColor)),
      ],
    );
  }
}

class _ToggleAuthMode extends StatefulWidget {
  const _ToggleAuthMode({required this.isSignUp, required this.onToggle});
  final bool isSignUp;
  final VoidCallback? onToggle;

  @override
  State<_ToggleAuthMode> createState() => _ToggleAuthModeState();
}

class _ToggleAuthModeState extends State<_ToggleAuthMode> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          widget.isSignUp
              ? 'Already have an account? '
              : "Don't have an account? ",
          style: text.bodyMedium,
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onToggle,
            child: Text(
              widget.isSignUp ? 'Sign in' : 'Sign up',
              style: text.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                decoration: _hovering ? TextDecoration.underline : null,
                decorationColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

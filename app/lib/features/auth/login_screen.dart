// app/lib/features/auth/login_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/r_star_badge.dart';
import 'auth_providers.dart';
import 'auth_validation.dart';
import 'forgot_password_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _showCompleteRegistrationAction = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Shared by both the normal email/password path and the biometric path
  /// -- the negotiator-status branch (pending/approved/rejected) must never
  /// drift between the two ways of arriving at a valid session.
  ///
  /// Returns true only once 'approved' status is confirmed, WITHOUT
  /// navigating to '/home' itself -- `_submit` navigates only after also
  /// offering biometric enrollment (see its own comment for why that must
  /// happen before navigation, and only once approved is confirmed).
  Future<bool> _handlePostSignIn(String userId) async {
    final repository = ref.read(authRepositoryProvider);
    final negotiator = await repository.fetchOwnNegotiator(userId);
    if (!mounted) return false;
    if (negotiator == null) {
      // No negotiator row for this session -- e.g. signUp() succeeded but
      // insertNegotiator() never ran (see auth_repository.dart). Sending
      // the user back through registration recovers this: Step 1's submit
      // handler now signs in with the same email/password on an
      // "already registered" error and upserts the missing row.
      setState(() {
        _errorMessage = 'auth_login_error_no_profile'.tr();
        _showCompleteRegistrationAction = true;
      });
      return false;
    }
    if (negotiator.verificationStatus == 'pending') {
      context.go('/verification-pending');
      return false;
    } else if (negotiator.verificationStatus == 'approved') {
      return true;
    } else {
      // No live session may survive a rejected login attempt.
      await repository.signOut();
      if (!mounted) return false;
      // signOut() clears the underlying biometric token, so the UI's stale
      // "Biometric login enabled" state must be invalidated too.
      ref.invalidate(biometricLoginEnabledProvider);
      setState(() => _errorMessage = 'auth_login_error_rejected'.tr());
      return false;
    }
  }

  /// Offered BEFORE any navigation happens (see `_submit`) -- showing this
  /// after `context.go(...)` races the screen's own disposal, and the
  /// dialog can silently never appear.
  ///
  /// "Not Now" is remembered via `has_dismissed_biometric_prompt` so the
  /// user is asked at most once; the Account Settings toggle stays
  /// available forever regardless.
  Future<void> _maybeOfferBiometricEnrollment() async {
    final repository = ref.read(authRepositoryProvider);
    final available = await repository.isBiometricAvailable();
    if (!available) return;
    final alreadyEnabled = await repository.hasBiometricLoginEnabled();
    if (alreadyEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('has_dismissed_biometric_prompt') ?? false;
    if (dismissed) return;
    if (!mounted) return;
    final wantsToEnable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('auth_biometric_prompt_title'.tr()),
        content: Text('auth_biometric_prompt_body'.tr()),
        actions: [
          BrutalistButton(
            label: 'auth_biometric_prompt_not_now'.tr(),
            variant: BrutalistButtonVariant.secondary,
            fullWidth: false,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          BrutalistButton(
            label: 'auth_biometric_prompt_enable'.tr(),
            fullWidth: false,
            icon: PhosphorIcons.fingerprint(PhosphorIconsStyle.bold),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (wantsToEnable == true) {
      try {
        await repository.enableBiometricLogin(localizedReason: 'auth_biometric_enable_reason'.tr());
        ref.invalidate(biometricLoginEnabledProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('auth_biometric_enable_success'.tr())),
          );
        }
      } catch (_) {
        // Enrollment failing (user cancelled the biometric prompt, etc.)
        // must never block the sign-in that already succeeded -- but it
        // must not be silent either, matching the Account Settings
        // toggle's own SnackBar-on-failure behaviour.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('listing_error_generic'.tr())),
          );
        }
      }
    } else {
      await prefs.setBool('has_dismissed_biometric_prompt', true);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _showCompleteRegistrationAction = false;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final response = await repository.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final userId = response.user?.id;
      if (userId == null) {
        setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
        return;
      }
      if (!mounted) return;
      // Status must be confirmed 'approved' BEFORE the enrollment offer --
      // offering biometrics to a still-pending or rejected negotiator would
      // let them enroll before their status is even known. The offer must
      // still come before navigation to '/home' below: a showDialog issued
      // after that navigation races this screen's disposal and can
      // silently never appear.
      final approved = await _handlePostSignIn(userId);
      if (!approved) return;
      try {
        await _maybeOfferBiometricEnrollment();
      } catch (_) {
        // Enrollment-offer is best-effort UX -- a failure here (e.g. a
        // local_auth plugin hiccup) must never block or misreport an
        // already-successful sign-in.
      }
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitWithBiometrics() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _showCompleteRegistrationAction = false;
    });
    final repository = ref.read(authRepositoryProvider);
    try {
      final response = await repository.signInWithBiometrics(
        localizedReason: 'auth_biometric_signin_reason'.tr(),
      );
      final userId = response.user?.id;
      if (userId == null) {
        setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
        return;
      }
      if (!mounted) return;
      final approved = await _handlePostSignIn(userId);
      if (approved && mounted) context.go('/home');
    } catch (_) {
      if (mounted) {
        // The stored token is gone (signInWithBiometrics clears it on
        // failure), so the Biometric button must disappear -- without this
        // invalidate it stays on screen, permanently broken.
        ref.invalidate(biometricLoginEnabledProvider);
        setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biometricEnabledAsync = ref.watch(biometricLoginEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RStarBadge(size: 28),
            const SizedBox(width: 8),
            Text(
              'app_name'.tr(),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.ink,
                    fontSize: 20,
                    letterSpacing: -1.0,
                    height: 1,
                  ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('auth_login_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('login_email_field'),
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'field_email'.tr(),
                    prefixIcon: Icon(PhosphorIcons.envelopeSimple(PhosphorIconsStyle.bold)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidEmail(value.trim())) return 'validation_email_invalid'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login_password_field'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'field_password'.tr(),
                    prefixIcon: Icon(PhosphorIcons.lockKey(PhosphorIconsStyle.bold)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? PhosphorIcons.eye(PhosphorIconsStyle.bold)
                            : PhosphorIcons.eyeSlash(PhosphorIconsStyle.bold),
                      ),
                      tooltip: _obscurePassword ? 'a11y_show_password'.tr() : 'a11y_hide_password'.tr(),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    // barrierDismissible: false -- the dialog pops itself
                    // once resetPasswordForEmail() resolves; a barrier tap
                    // mid-flight would pop it early and let that later pop
                    // take THIS screen off the stack instead.
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ForgotPasswordDialog(initialEmail: _emailController.text.trim()),
                    ),
                    child: Text('auth_forgot_password_link'.tr()),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (_showCompleteRegistrationAction)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push('/register/personal'),
                      child: Text('auth_complete_registration_action'.tr()),
                    ),
                  ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'auth_log_in'.tr(),
                  icon: PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register/personal'),
                  child: Text('auth_login_no_account'.tr()),
                ),
                biometricEnabledAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (enabled) => enabled
                      ? Column(
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('auth_or_continue_with'.tr()),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 8),
                            BrutalistButton(
                              label: 'auth_biometric_button'.tr(),
                              variant: BrutalistButtonVariant.secondary,
                              icon: PhosphorIcons.fingerprint(PhosphorIconsStyle.bold),
                              onPressed: _submitting ? null : _submitWithBiometrics,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

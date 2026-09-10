import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/r_star_badge.dart';
import 'auth_providers.dart';
import 'auth_validation.dart';
import 'password_recovery_state.dart';

/// Reached only via `app_router.dart`'s `computeAuthRedirect`, which locks
/// every navigation attempt here while [PasswordRecoveryState.isRecovering]
/// is true -- i.e. the app was opened via a Supabase "reset password" email
/// link (see `AuthRepository.resetPasswordForEmail`'s `redirectTo`). There
/// is deliberately no back/cancel action: the recovery session this screen
/// runs under is not a normal sign-in, so leaving without setting a new
/// password would strand the user in a half-authenticated state.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      await repository.updatePassword(_passwordController.text);
      // Cleared before signOut()/navigation -- otherwise computeAuthRedirect
      // would immediately bounce the post-sign-out '/login' navigation
      // straight back to this screen.
      PasswordRecoveryState.isRecovering = false;
      await repository.signOut();
      if (!mounted) return;
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('reset_password_success'.tr())),
      );
    } catch (_) {
      // The recovery link is single-use and expires (~1 hour); a second
      // attempt through it, or a very weak password, both throw here.
      if (mounted) setState(() => _submitError = 'reset_password_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
                Text('reset_password_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('reset_password_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('reset_password_field'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'field_password'.tr()),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidPassword(value)) return 'validation_password_too_short'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reset_confirm_password_field'),
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'field_confirm_password'.tr()),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.passwordsMatch(_passwordController.text, value)) {
                      return 'validation_password_mismatch'.tr();
                    }
                    return null;
                  },
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                BrutalistButton(
                  label: 'reset_password_submit'.tr(),
                  icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

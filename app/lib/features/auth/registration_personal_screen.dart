import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'auth_providers.dart';
import 'auth_validation.dart';

/// Ports stitch_renly_property_agent_network/registration_personal, with
/// email/password/confirm-password fields added ahead of the mockup's own
/// fullName/icNumber/phoneNumber fields (the mockup has no auth-credential
/// screen at all -- see the design doc's "Gap the mockups don't cover").
class RegistrationPersonalScreen extends ConsumerStatefulWidget {
  const RegistrationPersonalScreen({super.key});

  @override
  ConsumerState<RegistrationPersonalScreen> createState() => _RegistrationPersonalScreenState();
}

class _RegistrationPersonalScreenState extends ConsumerState<RegistrationPersonalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _icNumberController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _icNumberController.dispose();
    _phoneNumberController.dispose();
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
      final user = await repository.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await repository.insertNegotiator(
        negotiatorId: user.id,
        fullName: _fullNameController.text.trim(),
        icNumber: _icNumberController.text.trim(),
        phoneNumber: _phoneNumberController.text.trim(),
      );
      if (!mounted) return;
      context.push('/register/professional', extra: user.id);
    } catch (_) {
      // Never surface the raw exception: PostgrestException.toString() echoes
      // constraint-violation details (the offending IC/phone number) and
      // AuthException leaks account-enumeration info ("User already
      // registered").
      if (mounted) setState(() => _submitError = 'registration_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: Text('app_name'.tr()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('registration_step1_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('registration_step1_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('registration_personal_details_label'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary)),
                    Text('registration_step1_progress'.tr(), style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('reg_email_field'),
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'field_email'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidEmail(value.trim())) return 'validation_email_invalid'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_password_field'),
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
                  key: const Key('reg_confirm_password_field'),
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
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_full_name_field'),
                  controller: _fullNameController,
                  decoration: InputDecoration(labelText: 'field_full_name'.tr()),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_ic_number_field'),
                  controller: _icNumberController,
                  decoration: InputDecoration(labelText: 'field_ic_number'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidIcNumber(value.trim())) return 'validation_ic_invalid'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_phone_number_field'),
                  controller: _phoneNumberController,
                  decoration: InputDecoration(labelText: 'field_phone_number'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidPhoneNumber(value.trim())) return 'validation_phone_invalid'.tr();
                    return null;
                  },
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                      child: Text('registration_cancel'.tr()),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text('registration_next_step'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

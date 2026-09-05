import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_validation.dart';
import 'settings_providers.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(identityInfoProvider);

    return Scaffold(
      appBar: AppBar(title: Text('account_settings_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            infoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('listing_error_generic'.tr()),
                    TextButton(
                      onPressed: () => ref.invalidate(identityInfoProvider),
                      child: Text('agreement_retry'.tr()),
                    ),
                  ],
                ),
              ),
              data: (info) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${'account_settings_ic_label'.tr()}: ${info.icNumber ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('${'account_settings_phone_label'.tr()}: ${info.phoneNumber ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('${'profile_ren_number_label'.tr()}: ${info.renNumber ?? '-'}'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('account_settings_password_section_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const _PasswordForm(),
            const SizedBox(height: 20),
            const _BiometricToggle(),
          ],
        ),
      ),
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm();

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(settingsRepositoryProvider).updatePassword(_newPasswordController.text);
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('account_settings_password_success'.tr())),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: InputDecoration(labelText: 'account_settings_new_password_label'.tr()),
            validator: (value) =>
                AuthValidation.isValidPassword(value ?? '') ? null : 'validation_password_too_short'.tr(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: InputDecoration(labelText: 'account_settings_confirm_password_label'.tr()),
            validator: (value) => AuthValidation.passwordsMatch(_newPasswordController.text, value ?? '')
                ? null
                : 'validation_password_mismatch'.tr(),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          BrutalistButton(
            label: 'account_settings_submit'.tr(),
            icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _BiometricToggle extends ConsumerStatefulWidget {
  const _BiometricToggle();

  @override
  ConsumerState<_BiometricToggle> createState() => _BiometricToggleState();
}

class _BiometricToggleState extends ConsumerState<_BiometricToggle> {
  bool? _override;
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final repository = ref.read(authRepositoryProvider);
    try {
      if (value) {
        await repository.enableBiometricLogin(localizedReason: 'auth_biometric_enable_reason'.tr());
      } else {
        await repository.disableBiometricLogin();
      }
      setState(() => _override = value);
      ref.invalidate(biometricLoginEnabledProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableAsync = ref.watch(biometricAvailableProvider);
    final enabledAsync = ref.watch(biometricLoginEnabledProvider);

    return availableAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (available) {
        if (!available) return const SizedBox.shrink();
        return enabledAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => const SizedBox.shrink(),
          data: (enabled) => BrutalistCard(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: SwitchListTile(
                title: Text('account_settings_biometric_label'.tr()),
                value: _override ?? enabled,
                onChanged: _busy ? null : _toggle,
              ),
            ),
          ),
        );
      },
    );
  }
}

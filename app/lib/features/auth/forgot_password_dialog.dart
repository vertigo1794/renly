// app/lib/features/auth/forgot_password_dialog.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import 'auth_providers.dart';
import 'auth_validation.dart';

/// Always shows the same generic success copy regardless of whether the
/// email exists in the system or the resetPasswordForEmail() call throws
/// -- account-enumeration-safe, matching registration_personal_screen.dart's
/// own established reasoning for never surfacing a raw auth exception.
class ForgotPasswordDialog extends ConsumerStatefulWidget {
  const ForgotPasswordDialog({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final email = _emailController.text.trim();
    try {
      await ref.read(authRepositoryProvider).resetPasswordForEmail(email);
    } catch (_) {
      // Deliberately swallowed -- see class doc comment.
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth_forgot_password_success'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actionsOverflowButtonSpacing: 8,
      title: Text('auth_forgot_password_title'.tr()),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('forgot_password_email_field'),
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'field_email'.tr()),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
            if (!AuthValidation.isValidEmail(value.trim())) return 'validation_email_invalid'.tr();
            return null;
          },
        ),
      ),
      actions: [
        BrutalistButton(
          label: 'auth_forgot_password_cancel'.tr(),
          variant: BrutalistButtonVariant.secondary,
          fullWidth: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        BrutalistButton(
          label: 'auth_forgot_password_send'.tr(),
          fullWidth: false,
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_providers.dart';
import 'auth_validation.dart';

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
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
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
      final negotiator = await repository.fetchOwnNegotiator(userId);
      if (!mounted) return;
      if (negotiator == null) {
        setState(() => _errorMessage = 'auth_login_error_no_profile'.tr());
        return;
      }
      if (negotiator.verificationStatus == 'pending') {
        context.go('/verification-pending');
      } else {
        context.go('/home');
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('app_name'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('login_email_field'),
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'field_email'.tr()),
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
                  decoration: InputDecoration(labelText: 'field_password'.tr()),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('auth_log_in'.tr()),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register/personal'),
                  child: Text('auth_login_no_account'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

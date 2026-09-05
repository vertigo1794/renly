# Login Redesign + Password Reset + Biometric Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `LoginScreen` from Stitch's premium mockup and build 2 real features it implies: a Supabase password-reset dialog, and biometric sign-in (auto-refreshed session token, cleared on sign-out — revised post-implementation, see the design doc's "Design correction" section; a Supabase refresh token cannot both survive `signOut()` and stay usable).

**Architecture:** `local_auth` gates a `flutter_secure_storage`-held Supabase refresh token; restoring it calls `GoTrueClient.setSession`. The forgot-password dialog and Log In button both route through the same `AuthRepository`/Urby-system conventions already established elsewhere in this app.

**Tech Stack:** Flutter + Riverpod + Supabase (`supabase_flutter ^2.8.0`, `gotrue 2.27.2`) + `local_auth ^3.0.2` + `flutter_secure_storage ^11.0.0` + `phosphor_flutter ^2.1.0`.

## Global Constraints

- Google sign-in is dropped entirely, not stubbed/disabled — no dead button anywhere.
- No in-app "set new password" screen — password reset ends at sending the email; Supabase's own hosted page handles the rest.
- **REVISED post-implementation**: `AuthRepository.signOut()` now DOES clear the stored biometric token before signing out (a Supabase refresh token cannot survive `signOut()` server-side revocation and stay usable — see the design doc's "Design correction"). Originally this constraint said the opposite; that was proven wrong by the final whole-branch review.
- `LoginScreen`'s biometric button only renders when `biometricLoginEnabledProvider` resolves `true` (a stored token exists) — never shown disabled/grayed-out.
- The password-reset dialog ALWAYS shows the same generic success message regardless of whether the email exists or the call throws (account-enumeration-safe).
- All icons `PhosphorIcons.x(PhosphorIconsStyle.bold)`, never `Icons.*`.
- `flutter analyze` and the full `flutter test` suite must stay clean after every task.
- No golden-image tests.
- EN/MS l10n key parity maintained throughout.
- Supabase-boundary calls (repository methods hitting Postgres/Auth, `local_auth`, `flutter_secure_storage`) are not unit-tested — verified manually instead. Widget tests use provider overrides + `flutter_test`, following the exact pattern in `app/test/features/auth/login_screen_test.dart`.

---

### Task 1: Add `local_auth` + `flutter_secure_storage` dependencies

**Files:**
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Produces: `local_auth: ^3.0.2`, `flutter_secure_storage: ^11.0.0` available to all later tasks. `LocalAuthentication` class (`authenticate({required String localizedReason, bool biometricOnly})` → `Future<bool>`, `canCheckBiometrics` getter → `Future<bool>`, `isDeviceSupported()` → `Future<bool>`). `FlutterSecureStorage` class (`write({required String key, required String? value})`, `read({required String key})` → `Future<String?>`, `delete({required String key})`, `containsKey({required String key})` → `Future<bool>`) — all 4 signatures already confirmed this session against the actual installed package source, use them verbatim in Task 2.

- [ ] **Step 1: Add the dependencies**

Run: `cd app && flutter pub add local_auth flutter_secure_storage`
Expected: `pubspec.yaml` gains `local_auth: ^3.0.2` and `flutter_secure_storage: ^11.0.0` under `dependencies:`, `pubspec.lock` updates, and several platform-registrant files (`linux/flutter/generated_plugin_registrant.cc`, `macos/Flutter/GeneratedPluginRegistrant.swift`, `windows/flutter/generated_plugin_registrant.cc`, etc.) regenerate — this is expected, commit them along with the rest.

- [ ] **Step 2: Confirm the app still analyzes and tests clean with the new dependencies present but unused**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!`, full existing suite passes unchanged (236/236 or whatever the current count is — no test references these packages yet).

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/linux/flutter/generated_plugin_registrant.cc app/linux/flutter/generated_plugins.cmake app/macos/Flutter/GeneratedPluginRegistrant.swift app/windows/flutter/generated_plugin_registrant.cc app/windows/flutter/generated_plugins.cmake
git commit -m "chore: add local_auth and flutter_secure_storage dependencies"
```

---

### Task 2: `AuthRepository` additions (password reset + biometric)

**Files:**
- Modify: `app/lib/features/auth/auth_repository.dart`

**Interfaces:**
- Consumes: Task 1's `local_auth`/`flutter_secure_storage` packages. Existing `SupabaseClient _client` field, existing constructor `AuthRepository(this._client)` (unchanged).
- Produces: `resetPasswordForEmail(String email) -> Future<void>`, `isBiometricAvailable() -> Future<bool>`, `enableBiometricLogin({required String localizedReason}) -> Future<void>`, `disableBiometricLogin() -> Future<void>`, `hasBiometricLoginEnabled() -> Future<bool>`, `signInWithBiometrics({required String localizedReason}) -> Future<AuthResponse>`. Task 3's providers and Task 4's `LoginScreen`/dialog consume these directly.

- [ ] **Step 1: Add the imports and private fields**

At the top of `app/lib/features/auth/auth_repository.dart`, add:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
```

Inside the `AuthRepository` class, right after the existing `final SupabaseClient _client;` field, add:

```dart
  final LocalAuthentication _localAuth = LocalAuthentication();
  static const _secureStorage = FlutterSecureStorage();
  static const _biometricTokenKey = 'biometric_refresh_token';
```

- [ ] **Step 2: Add `resetPasswordForEmail`**

Add this method anywhere among the other public methods (e.g. right after `signOut()`):

```dart
  Future<void> resetPasswordForEmail(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }
```

- [ ] **Step 3: Add the 4 biometric-support methods**

```dart
  Future<bool> isBiometricAvailable() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final supported = await _localAuth.isDeviceSupported();
    return canCheck && supported;
  }

  /// Confirms the user's biometric identity, then stores the CURRENT
  /// session's refresh token -- deliberately not cleared by signOut() (a
  /// stored token surviving sign-out is what makes this feature useful:
  /// "I signed out yesterday, let me back in quickly today").
  Future<void> enableBiometricLogin({required String localizedReason}) async {
    final authenticated = await _localAuth.authenticate(localizedReason: localizedReason);
    if (!authenticated) {
      throw StateError('Biometric authentication was not completed.');
    }
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('No active session to enable biometric login for.');
    }
    await _secureStorage.write(key: _biometricTokenKey, value: session.refreshToken);
  }

  Future<void> disableBiometricLogin() {
    return _secureStorage.delete(key: _biometricTokenKey);
  }

  Future<bool> hasBiometricLoginEnabled() {
    return _secureStorage.containsKey(key: _biometricTokenKey);
  }
```

- [ ] **Step 4: Add `signInWithBiometrics`**

```dart
  /// Restores the session from the stored refresh token after a successful
  /// biometric check. If the stored token itself is invalid/expired (rare,
  /// but real -- Supabase can revoke a refresh token server-side), clears
  /// it so `hasBiometricLoginEnabled()` -> the Biometric button disappears
  /// -- rather than leaving a permanently-broken button behind.
  Future<AuthResponse> signInWithBiometrics({required String localizedReason}) async {
    final authenticated = await _localAuth.authenticate(localizedReason: localizedReason);
    if (!authenticated) {
      throw StateError('Biometric authentication was not completed.');
    }
    final token = await _secureStorage.read(key: _biometricTokenKey);
    if (token == null) {
      throw StateError('No stored biometric credential.');
    }
    try {
      return await _client.auth.setSession(token);
    } catch (e) {
      await _secureStorage.delete(key: _biometricTokenKey);
      rethrow;
    }
  }
```

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!` — this step is where any mismatch between this plan's assumed `local_auth`/`flutter_secure_storage` API and the actually-resolved package version would surface as a compile error. If it does, fix the call to match whatever the installed package's real signature is (re-check `~/.pub-cache/hosted/pub.dev/local_auth-3.0.2/lib/src/local_auth.dart` and `~/.pub-cache/hosted/pub.dev/flutter_secure_storage-11.0.0/lib/flutter_secure_storage.dart` directly rather than guessing further).

- [ ] **Step 6: Run the full test suite**

Run: `cd app && flutter test`
Expected: all existing tests still pass (this task adds no new test file — `AuthRepository` methods are Supabase/local_auth/secure_storage-boundary calls, manually verified per this project's established convention, not unit-tested).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/auth/auth_repository.dart
git commit -m "feat: add password reset and biometric sign-in to AuthRepository"
```

---

### Task 3: New providers in `auth_providers.dart`

**Files:**
- Modify: `app/lib/features/auth/auth_providers.dart`

**Interfaces:**
- Consumes: Task 2's `AuthRepository.isBiometricAvailable()`/`hasBiometricLoginEnabled()`, existing `authRepositoryProvider`.
- Produces: `biometricAvailableProvider` (`FutureProvider<bool>`), `biometricLoginEnabledProvider` (`FutureProvider<bool>`). Task 4's `LoginScreen` and Task 5's `AccountSettingsScreen` both watch these.

- [ ] **Step 1: Add the 2 providers**

At the bottom of `app/lib/features/auth/auth_providers.dart`, add:

```dart
/// Whether this device supports biometric authentication at all (hardware
/// + enrollment) -- device-local capability, NOT negotiator-scoped (unlike
/// settings_providers.dart's pattern, which gates server-backed prefs on
/// currentNegotiatorIdProvider).
final biometricAvailableProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).isBiometricAvailable();
});

/// Whether a biometric-gated refresh token is currently stored on this
/// device -- LoginScreen's biometric button only renders when this
/// resolves true.
final biometricLoginEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).hasBiometricLoginEnabled();
});
```

- [ ] **Step 2: Run `flutter analyze` and the full test suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!`, all existing tests pass (purely additive, no consumer yet).

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/auth/auth_providers.dart
git commit -m "feat: add biometricAvailableProvider and biometricLoginEnabledProvider"
```

---

### Task 4: `LoginScreen` restyle + forgot-password dialog + biometric wiring

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart`
- Create: `app/lib/features/auth/forgot_password_dialog.dart`
- Modify: `app/test/features/auth/login_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: Task 2's `AuthRepository.resetPasswordForEmail`/`enableBiometricLogin`/`signInWithBiometrics`, Task 3's `biometricAvailableProvider`/`biometricLoginEnabledProvider`, existing `RStarBadge`, `BrutalistButton` (`icon`/`variant`/`fullWidth` params), `AppColors`.
- Produces: `ForgotPasswordDialog` widget (`showDialog(context: context, builder: (_) => const ForgotPasswordDialog())`). `LoginScreen`'s restyled body — nothing later depends on this screen's internals.

- [ ] **Step 1: Read the current `login_screen_test.dart` and confirm the exact effect of the new providers on its 2 existing tests**

Run: `cat -n app/test/features/auth/login_screen_test.dart`
Expected: confirms the 2 existing tests (`renders email and password fields`, `submitting with empty fields shows validation errors and does not submit`) use a bare `ProviderScope` with no overrides. Once `LoginScreen` watches `biometricLoginEnabledProvider` (Step 4 below), that provider will call `AuthRepository.hasBiometricLoginEnabled()` → `FlutterSecureStorage.containsKey()`, which has no platform channel in the widget-test environment and would throw — both existing tests need `biometricLoginEnabledProvider.overrideWith((ref) async => false)` added to their `ProviderScope`. Step 6 below updates this file.

- [ ] **Step 2: Write `ForgotPasswordDialog`**

```dart
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
```

- [ ] **Step 3: Add the 4 new l10n keys for the dialog**

Add to `app/assets/translations/en.json`: `"auth_forgot_password_title": "Reset Password"`, `"auth_forgot_password_cancel": "Cancel"`, `"auth_forgot_password_send": "Send Link"`, `"auth_forgot_password_success": "Check your email for a reset link."`.
Add the matching Malay values to `app/assets/translations/ms.json`, matching the style/placement of neighboring auth-related keys in that file.

- [ ] **Step 4: Rewrite `LoginScreen`**

```dart
// app/lib/features/auth/login_screen.dart
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
import 'forgot_password_dialog.dart';
import 'models/negotiator.dart';

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Shared by both the normal email/password path and the biometric path
  /// -- the negotiator-status branch (pending/approved/rejected) must never
  /// drift between the two ways of arriving at a valid session.
  Future<void> _handlePostSignIn(String userId) async {
    final repository = ref.read(authRepositoryProvider);
    final negotiator = await repository.fetchOwnNegotiator(userId);
    if (!mounted) return;
    if (negotiator == null) {
      setState(() => _errorMessage = 'auth_login_error_no_profile'.tr());
      return;
    }
    if (negotiator.verificationStatus == 'pending') {
      context.go('/verification-pending');
    } else if (negotiator.verificationStatus == 'approved') {
      context.go('/home');
    } else {
      setState(() => _errorMessage = 'auth_login_error_rejected'.tr());
    }
  }

  Future<void> _maybeOfferBiometricEnrollment() async {
    final repository = ref.read(authRepositoryProvider);
    final available = await repository.isBiometricAvailable();
    if (!available) return;
    final alreadyEnabled = await repository.hasBiometricLoginEnabled();
    if (alreadyEnabled) return;
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
      } catch (_) {
        // Enrollment failing (user cancelled the biometric prompt, etc.)
        // must never block the sign-in that already succeeded.
      }
    }
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
      await _handlePostSignIn(userId);
      if (mounted && _errorMessage == null) {
        await _maybeOfferBiometricEnrollment();
      }
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
      await _handlePostSignIn(userId);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
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
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => ForgotPasswordDialog(initialEmail: _emailController.text.trim()),
                    ),
                    child: Text('auth_forgot_password_link'.tr()),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
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
```

Note: the unused `Negotiator` import can be removed if `flutter analyze` flags it as unused — it was only needed if this file referenced the `Negotiator` type directly, which it no longer does now that `_handlePostSignIn` reads the type implicitly via `repository.fetchOwnNegotiator`'s return type. Remove that import in Step 5 if analyze flags it.

- [ ] **Step 5: Add the remaining new l10n keys**

Add to `app/assets/translations/en.json`: `"auth_login_subtitle": "Sign in to your co-broking network and verified MLS listings."`, `"auth_forgot_password_link": "Forgot password?"`, `"auth_biometric_prompt_title": "Enable Biometric Login?"`, `"auth_biometric_prompt_body": "Sign in faster next time using your fingerprint or face."`, `"auth_biometric_prompt_not_now": "Not Now"`, `"auth_biometric_prompt_enable": "Enable"`, `"auth_biometric_enable_reason": "Confirm your identity to enable biometric login"`, `"auth_biometric_signin_reason": "Sign in to Renly"`, `"auth_or_continue_with": "OR CONTINUE WITH"`, `"auth_biometric_button": "Biometric / REN"`.
Add the matching Malay values to `app/assets/translations/ms.json`.

- [ ] **Step 6: Update `login_screen_test.dart`**

Replace the file's `_wrap` helper and both tests to override `biometricLoginEnabledProvider` (per Step 1's reasoning):

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/auth/auth_providers.dart';
import 'package:renly/features/auth/login_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      biometricLoginEnabledProvider.overrideWith((ref) async => false),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp.router(
          theme: AppTheme.light,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: router,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders email and password fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
  });

  testWidgets('submitting with empty fields shows validation errors and does not submit', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('password visibility toggle switches obscureText', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    TextField passwordField() => tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('login_password_field')), matching: find.byType(TextField)),
        );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byIcon(PhosphorIcons.eye(PhosphorIconsStyle.bold)));
    await tester.pumpAndSettle();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('biometric button is hidden when biometricLoginEnabledProvider resolves false', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Biometric / REN'), findsNothing);
  });

  testWidgets('biometric button is shown when biometricLoginEnabledProvider resolves true', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [biometricLoginEnabledProvider.overrideWith((ref) async => true)],
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ms')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp.router(
              theme: AppTheme.light,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              routerConfig: router,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Biometric / REN'), findsOneWidget);
  });

  testWidgets('forgot password link opens dialog with generic success message', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot_password_email_field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('forgot_password_email_field')), 'agent@renly.my');
    await tester.tap(find.text('Send Link'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email for a reset link.'), findsOneWidget);
  });
}
```

Note: the last test (`resetPasswordForEmail`) will hit `Supabase.instance.client` inside `AuthRepository.resetPasswordForEmail` and throw since Supabase isn't initialized in the test environment — per `ForgotPasswordDialog`'s own `try { ... } catch (_) {}` (Step 2 above), this is caught and the generic success message shows regardless, exactly matching this plan's account-enumeration-safe requirement and this project's established Task-5-style "fire-and-forget catch, still show success" pattern from the Main Nav plan.

Need `import 'package:phosphor_flutter/phosphor_flutter.dart';` added to this test file's imports for the `PhosphorIcons.eye(...)` reference in the visibility-toggle test — add it alongside the other imports.

- [ ] **Step 7: Run the full test suite**

Run: `cd app && flutter test test/features/auth/login_screen_test.dart`
Expected: all tests in this file pass (7 total: the original 2 + 5 new).

- [ ] **Step 8: Run the full suite and `flutter analyze`**

Run: `cd app && flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`. If `flutter analyze` flags the `Negotiator` import in `login_screen.dart` as unused (per Step 4's note), remove it.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/auth/login_screen.dart app/lib/features/auth/forgot_password_dialog.dart app/test/features/auth/login_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: restyle LoginScreen, add forgot-password dialog and biometric sign-in"
```

---

### Task 5: `AccountSettingsScreen` biometric toggle

**Files:**
- Modify: `app/lib/features/settings/account_settings_screen.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`
- Test: `app/test/features/settings/account_settings_screen_test.dart` (check if this file already exists first — read it before assuming its current content)

**Interfaces:**
- Consumes: Task 3's `biometricAvailableProvider`/`biometricLoginEnabledProvider`, Task 2's `AuthRepository.enableBiometricLogin`/`disableBiometricLogin`, existing `BrutalistCard`.
- Produces: nothing consumed by a later task — this is the last task in this plan.

- [ ] **Step 1: Read the existing `account_settings_screen_test.dart` if it exists**

Run: `ls app/test/features/settings/account_settings_screen_test.dart 2>&1; cat -n app/test/features/settings/account_settings_screen_test.dart 2>&1`
Expected: confirms whether this test file exists and, if so, its current provider-override setup — the new toggle's own test additions must not collide with existing overrides.

- [ ] **Step 2: Add the biometric toggle section to `account_settings_screen.dart`**

Add this new private widget below `_PasswordForm` in `app/lib/features/settings/account_settings_screen.dart`:

```dart
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
```

Add the import `import '../auth/auth_providers.dart';` to the top of `account_settings_screen.dart` (if not already present via another import) and insert `const SizedBox(height: 20), const _BiometricToggle(),` right after the existing `const _PasswordForm(),` line in `AccountSettingsScreen.build`.

- [ ] **Step 3: Add the 1 new l10n key**

Add to `app/assets/translations/en.json`: `"account_settings_biometric_label": "Enable Biometric Login"`.
Add the matching Malay value to `app/assets/translations/ms.json`.

- [ ] **Step 4: Write or update the widget test**

If `account_settings_screen_test.dart` did not exist (per Step 1), create it:

```dart
// app/test/features/settings/account_settings_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/auth_providers.dart';
import 'package:renly/features/settings/account_settings_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('biometric toggle hidden when unavailable', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricAvailableProvider.overrideWith((ref) async => false),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ms')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const AccountSettingsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable Biometric Login'), findsNothing);
  });

  testWidgets('biometric toggle shown and reflects enabled state when available', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricAvailableProvider.overrideWith((ref) async => true),
          biometricLoginEnabledProvider.overrideWith((ref) async => true),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ms')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const AccountSettingsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable Biometric Login'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isTrue);
  });
}
```

If the file already existed with real content (per Step 1's read), add these 2 test cases to it instead of creating a new file, matching whatever `_wrap`-equivalent helper that file already established rather than duplicating a second one.

- [ ] **Step 5: Run the tests**

Run: `cd app && flutter test test/features/settings/account_settings_screen_test.dart`
Expected: both new tests pass.

- [ ] **Step 6: Run the full suite and `flutter analyze`**

Run: `cd app && flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/settings/account_settings_screen.dart app/test/features/settings/account_settings_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add biometric login toggle to Account Settings"
```

---

## Manual verification checklist (after all 5 tasks are code-complete)

Android emulators support enrolling a software fingerprint via `adb -e emu finger touch <finger_id>` (Extended Controls → Fingerprint, or the `adb` equivalent) — this project's emulator has no real biometric hardware, so this is the established path to test biometric flows on it, not a blocker:

1. Sign in normally with real credentials — confirm the "Enable Biometric Login?" dialog appears (assuming the emulator has a fingerprint enrolled), Enable → confirm the fingerprint prompt appears, confirm it lands on the correct post-login screen exactly as before this milestone.
2. Sign out, reopen the app, confirm the Biometric button now appears on `LoginScreen`, tap it, confirm the same fingerprint prompt + successful sign-in to the same account.
3. In Account Settings, toggle biometric off, confirm the Biometric button disappears from `LoginScreen` on next visit; toggle it back on (via a fresh fingerprint confirm), confirm it reappears.
4. Tap "Forgot password?", submit a real email, confirm the generic success message appears; check the email inbox for the actual reset link (confirms `resetPasswordForEmail` really fired against the live Supabase project).
5. Confirm the password visibility toggle actually shows/hides the typed password.
6. Confirm the AppBar back button returns to `AuthSelectionScreen` correctly.

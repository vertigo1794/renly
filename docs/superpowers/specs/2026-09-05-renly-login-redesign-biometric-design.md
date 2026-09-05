# renly — Login Screen Redesign + Password Reset + Biometric Sign-In Design

## Goal

Restyle `LoginScreen` (never touched by any prior Urby Restyle pass — still a bare `Scaffold`+`Form`+plain `TextFormField`) from Stitch's "Login - Redesigned Premium Style" mockup (project `13581751397915601898`, screen `a677989f6afd49cd8cafac76028c9f4e`), and build two real features the mockup implies but this app doesn't have yet: a password-reset flow, and biometric sign-in.

## Source of truth

Stitch mockup: back button, a pulsing status dot, "renly" wordmark + lime dot accent, subtitle, Email field (mail icon), Password field (lock icon + show/hide toggle), "Forgot password?" link, lime "Log In" button (hard-offset shadow, arrow icon), "OR CONTINUE WITH" divider, Google + Biometric/REN buttons, "Don't have an account? Create one" footer, a bottom trust badge ("Official Malaysia REN Verified Network") + home-indicator bar.

**Visual language**: rendered through this app's existing Urby/neo-brutalist system (`BrutalistButton`/`BrutalistCard`/`AppColors`/`PhosphorIcons`/`RStarBadge`), matching every other Stitch adaptation this session — not Stitch's own soft-shadow Material3 look. This was settled without re-litigating; it's this project's standing convention.

## Gaps between the mockup and this app's real backend

- **No forgot-password feature exists anywhere** (confirmed via grep: no route, no repository method, nothing calls Supabase's `resetPasswordForEmail`). Built for real this round (see below), not skipped.
- **Google sign-in**: dropped entirely, not stubbed. This Supabase project has no Google OAuth provider configured; wiring one is a separate, out-of-scope task.
- **Biometric/REN sign-in**: this app has zero biometric infrastructure today (no `local_auth`, no `flutter_secure_storage`). Built for real this round as an actual authentication mechanism, not a decorative button.
- **The pulsing status dot and mockup's own custom back-button chrome**: not adapted — `LoginScreen` reuses the exact `AppBar` + `RStarBadge` + wordmark header already established by `RegistrationPersonalScreen` (`BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'))`, centered title with `RStarBadge(size: 28)` + `app_name`), for header consistency across the auth flow rather than a one-off mockup-specific header treatment. The bottom trust-badge line is kept as inert, static copy (no interactivity implied, so no functionality gap).

## Screen layout (Urby adaptation)

- `AppBar`: `BackButton` (pops to `AuthSelectionScreen`, the only place that pushes `/login`) + centered `RStarBadge(28)` + `app_name` wordmark, identical styling to `RegistrationPersonalScreen`'s header.
- Subtitle text kept, styled `bodyMedium`.
- Email field: existing `TextFormField` gains `prefixIcon: Icon(PhosphorIcons.envelopeSimple(PhosphorIconsStyle.bold))`, matching the established field-icon convention from `RegistrationPersonalScreen`'s name/IC/phone fields.
- Password field: gains `prefixIcon: Icon(PhosphorIcons.lockKey(PhosphorIconsStyle.bold))` and a new `suffixIcon` — an `IconButton` toggling a new `_obscurePassword` bool (`eye`/`eyeSlash` icons) — this show/hide interaction does not exist on ANY text field in this app yet; first use of the pattern.
- "Forgot password?" — a `TextButton`-style link aligned to the row above the password field (mirroring the mockup's label-row layout), opens the reset dialog (below).
- `BrutalistButton(label: 'auth_log_in'.tr(), icon: PhosphorIcons.arrowRight(...), onPressed: _submit)` replaces the current label-only button.
- "Don't have an account? Create one" — unchanged (`context.push('/register/personal')`).
- Divider "OR CONTINUE WITH" + a single `BrutalistButton(variant: secondary, icon: PhosphorIcons.fingerprint(...))` biometric button — **only rendered when `biometricLoginEnabledProvider` is `true`** (a stored token exists); no button, no divider, nothing shown otherwise (no dead/disabled UI for the dropped Google option or for devices without biometric enrolled).
- Trust-badge footer line: static `Row` with a small icon + `Text`, no route/action attached.

## Password reset

A `showDialog` (not a new screen/route), triggered from "Forgot password?":

- One email `TextFormField`, pre-filled with whatever's already typed in the login screen's own email controller (if any).
- Actions: `BrutalistButton(variant: secondary, fullWidth: false)` Cancel + `BrutalistButton(fullWidth: false, icon: check)` Send — same `AlertDialog.actions` pattern already established by `ProposeAgreementDialog`/`RateDialog` from the Urby Restyle Phase 2B pass.
- Confirm calls `AuthRepository.resetPasswordForEmail(email)` → `_client.auth.resetPasswordForEmail(email)`.
- **Always shows the same generic success message** ("Check your email for a reset link.") regardless of whether the email exists in the system or the call throws — matching this project's own established account-enumeration-safe pattern (`registration_personal_screen.dart`'s own comment: "Never surface the raw exception... leaks account-enumeration info"). The actual password change happens entirely outside this app, via Supabase's own hosted reset-confirmation page reached from the emailed link — no in-app "set new password" screen is needed or built.

## Biometric sign-in

**New dependencies**: `local_auth` (biometric prompt) + `flutter_secure_storage` (Keystore/Keychain-backed storage for the stored refresh token) — both standard, widely-used Flutter packages, no alternatives considered.

**Mechanism**: after a normal successful email/password sign-in, the current Supabase session's refresh token can be stored in secure storage, gated behind a biometric prompt. On a later app open where no live Supabase session exists (explicit sign-out, or a session that expired), tapping the Biometric button re-authenticates via `local_auth.authenticate()` and, on success, calls `Supabase.instance.client.auth.setSession(storedRefreshToken)` (confirmed present on the pinned `gotrue 2.27.2`/`supabase_flutter ^2.8.0`) to restore the session — then follows the exact same post-sign-in negotiator-status branch (`pending`→`/verification-pending`, `approved`→`/home`, else→rejected message) that normal login already has. This branch is extracted into one shared private method both the normal-submit path and the biometric path call, so the two paths cannot drift.

**Enable/disable and persistence** (per this round's decisions):
- **Enrollment**: after a normal successful login, if the device supports biometrics (`local_auth.canCheckBiometrics && isDeviceSupported()`) AND biometric login isn't already enabled AND the user hasn't previously dismissed the one-time prompt (`has_dismissed_biometric_prompt` flag, `shared_preferences`), show a dialog: "Enable biometric login for faster sign-in next time?" [Not Now] / [Enable]. "Not Now" sets the dismissed flag (asked once, not nagged every login) — the Settings toggle remains available anytime regardless. "Enable" triggers `local_auth.authenticate()` as a confirmation step, then stores `session.refreshToken` in secure storage.
- **Settings toggle**: `AccountSettingsScreen` gains a `SwitchListTile` "Enable Biometric Login", visible only when the device supports biometrics, wrapped in a `BrutalistCard` matching `NotificationSettingsScreen`'s existing `SwitchListTile`-in-`BrutalistCard`+`Material` convention. Off→On triggers the same `local_auth.authenticate()` confirmation + token store; On→Off just clears the stored token (no biometric prompt needed to disable).
- **Survives explicit sign-out**: `AuthRepository.signOut()` is NOT changed to clear the stored biometric token — this was the explicit, deliberate choice this round (the token needs to outlive a sign-out to be useful: "I signed out yesterday, let me back in quickly today").
- **Stored-token invalidity**: if `setSession()` throws (the stored refresh token was itself revoked/expired beyond Supabase's refresh window — a real but infrequent case), the failure is treated as "biometric login no longer works" — the stored token is cleared, the Biometric button disappears (since `biometricLoginEnabledProvider` now reads false), and the user sees a generic sign-in error, falling back to normal email/password entry. No silent retry loop.

**New `AuthRepository` methods** (the only file that talks to Supabase for this feature, per its own existing convention):
```dart
Future<void> resetPasswordForEmail(String email);
Future<bool> isBiometricAvailable(); // wraps local_auth's canCheckBiometrics && isDeviceSupported
Future<void> enableBiometricLogin(); // authenticate() then store currentSession's refresh token
Future<void> disableBiometricLogin(); // clear stored token, no prompt
Future<bool> hasBiometricLoginEnabled(); // secure storage read, token present?
Future<AuthResponse> signInWithBiometrics(); // authenticate() then setSession(storedToken); clears token + rethrows on failure
```

## Testing approach

Following this project's established convention: Supabase-boundary calls are not unit-tested (manual verification instead); pure logic and widget rendering get real tests.

- Widget tests for `LoginScreen`: field icons render, password visibility toggle flips `obscureText`, biometric button only renders when `biometricLoginEnabledProvider` resolves `true` (provider override), forgot-password dialog opens and always shows the generic success copy on confirm (repository call mocked/overridden to both succeed and throw, same expected message either way).
- Widget test for the new `AccountSettingsScreen` toggle: renders only when a `isBiometricAvailableProvider` override is `true`, on/off calls the right repository method.
- `local_auth`/`flutter_secure_storage`/actual Supabase calls: manually verified on the emulator (this project's emulator does not have real biometric hardware — Android emulators support a software fingerprint sensor "enrollment" via `adb`, which is the establish path to test this manually; noted for the manual verification checklist, not a blocker for the automated suite).

## Explicitly deferred / out of scope

- Google sign-in (dropped, not built).
- An in-app "set new password" screen — the reset flow ends at sending the email; the actual password change happens on Supabase's own hosted page.
- iOS Face ID/Touch ID testing (this project has been Android-only throughout, per the Push Notifications design's own established platform scope).
- Any change to `AuthRepository.signOut()`'s behavior beyond leaving the biometric token untouched (explicitly decided, not accidentally omitted).

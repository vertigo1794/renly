import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/negotiator.dart';

/// The only file in this app that talks to Supabase for auth/registration.
/// Screens call these methods; nothing else touches `SupabaseClient` for
/// this feature.
class AuthRepository {
  /// Subscribes to Supabase's auth-state stream for the lifetime of this
  /// repository so the stored biometric refresh token never goes stale.
  /// Supabase ROTATES the refresh token on every use -- including
  /// supabase_flutter's own hourly background auto-refresh -- so a token
  /// captured once at enrollment and never updated stops working within
  /// about an hour. Re-writing it on every `signedIn`/`tokenRefreshed`
  /// event is what makes biometric sign-in survive an app restart at all.
  AuthRepository(this._client) {
    _client.auth.onAuthStateChange.listen(
      (state) async {
        try {
          if (state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.tokenRefreshed) {
            if (await hasBiometricLoginEnabled()) {
              final refreshToken = state.session?.refreshToken;
              if (refreshToken != null) {
                await _secureStorage.write(key: _biometricTokenKey, value: refreshToken);
              }
            }
          }
        } catch (_) {
          // Best-effort token-freshness sync -- a failure here (e.g. a
          // transient secure-storage hiccup) must never crash the app; the
          // next successful auth event will simply retry the write.
        }
      },
      onError: (_) {
        // Network/stream errors on this listener (e.g. offline token
        // refresh failures) are non-fatal for the same reason -- best-effort
        // sync, not a required operation.
      },
    );
  }

  final SupabaseClient _client;
  final LocalAuthentication _localAuth = LocalAuthentication();
  static const _secureStorage = FlutterSecureStorage();
  static const _biometricTokenKey = 'biometric_refresh_token';

  Future<User> signUp({required String email, required String password}) async {
    final response = await _client.auth.signUp(email: email, password: password);
    final user = response.user;
    if (user == null) {
      throw StateError('Sign up succeeded but no user was returned.');
    }
    return user;
  }

  /// Upsert, not insert: signUp() can succeed while this call never runs
  /// (network drop, app killed) leaving a stranded auth user with no
  /// negotiator row. Registering again with the same email recovers via
  /// sign-in + a second call to this same method (see
  /// registration_personal_screen.dart's submit handler) -- that retry must
  /// not fail on a duplicate-key violation.
  ///
  /// ignoreDuplicates: true -- a plain upsert compiles to
  /// `INSERT ... ON CONFLICT DO UPDATE`, which Postgres requires UPDATE
  /// privilege for even when no conflict occurs at runtime. This table only
  /// grants INSERT on these columns (UPDATE is deliberately revoked, see
  /// 0002_rls_hardening.sql/0010_profile.sql), so a plain upsert failed with
  /// a permission error on EVERY signup, not just the recovery path -- same
  /// ON CONFLICT DO NOTHING fix already used by MatchingRepository._store
  /// for the identical reason.
  Future<void> insertNegotiator({
    required String negotiatorId,
    required String fullName,
    required String icNumber,
    required String phoneNumber,
  }) {
    return _client.from('negotiator').upsert(
      {
        'negotiator_id': negotiatorId,
        'full_name': fullName,
        'ic_number': icNumber,
        'phone_number': phoneNumber,
      },
      onConflict: 'negotiator_id',
      ignoreDuplicates: true,
    );
  }

  /// Finds an existing agency by case-insensitive name match, or creates
  /// one. Not atomic (select-then-insert) -- the DB's unique index on
  /// `lower(trim(firm_name))` is the backstop against a race between two
  /// concurrent registrations picking the same new agency name; a race
  /// surfaces as a Postgrest unique-violation the caller can ask the user
  /// to retry, which is an acceptable rare-edge-case for this milestone.
  Future<String> findOrCreateAgency(String firmName) async {
    final normalized = firmName.trim();
    // `ilike` treats %, _ as wildcards, and PostgREST also treats * as an
    // alias for % in ilike patterns, so an agency name like "IQI%" or
    // "IQI*" would match any agency starting with "IQI" (silently linking
    // the wrong one) and a bare "%"/"*" would match everything (making
    // maybeSingle() throw). Escape them for the FILTER only -- the
    // unescaped `normalized` is what gets stored.
    final escapedForIlike = normalized
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_')
        .replaceAll('*', '\\*');
    final existing = await _client
        .from('agency')
        .select('agency_id')
        .ilike('firm_name', escapedForIlike)
        .maybeSingle();
    if (existing != null) {
      return existing['agency_id'] as String;
    }
    final inserted = await _client
        .from('agency')
        .insert({'firm_name': normalized})
        .select('agency_id')
        .single();
    return inserted['agency_id'] as String;
  }

  Future<String> uploadTagPhoto({
    required String negotiatorId,
    required Uint8List bytes,
  }) async {
    final path = '$negotiatorId/tag.jpg';
    await _client.storage.from('ren-tags').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  Future<void> completeProfessionalDetails({
    required String negotiatorId,
    required String renNumber,
    required String agencyId,
  }) {
    return _client.from('negotiator').update({
      'ren_number': renNumber,
      'agency_id': agencyId,
    }).eq('negotiator_id', negotiatorId);
  }

  /// `verification_record` is an append-only audit trail by design (no
  /// unique constraint on negotiator_id -- see the schema comment in
  /// supabase/migrations/0001_auth_verification.sql), meant to hold one row
  /// per verification ATTEMPT over a negotiator's lifetime (e.g. a future
  /// reject-then-resubmit flow). So this does not add a schema constraint;
  /// it only skips the insert when a 'pending' record for this SAME
  /// in-progress registration already exists, guarding against Step 2's
  /// submit chain being retried after this insert already succeeded once.
  Future<void> insertVerificationRecord({
    required String negotiatorId,
    required String tagPhotoUrl,
  }) async {
    final existing = await _client
        .from('verification_record')
        .select('record_id')
        .eq('negotiator_id', negotiatorId)
        .eq('outcome', 'pending')
        .maybeSingle();
    if (existing != null) return;
    await _client.from('verification_record').insert({
      'negotiator_id': negotiatorId,
      'tag_photo_url': tagPhotoUrl,
    });
  }

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Clears the stored biometric token BEFORE signing out. GoTrue's
  /// default (`local`) sign-out scope revokes the session's refresh token
  /// server-side, so a token kept across sign-out would be dead anyway --
  /// keeping it would only leave a permanently-broken Biometric button on
  /// the login screen. Biometric sign-in is scoped as quick re-entry for
  /// an interrupted/backgrounded session, NOT re-entry after an explicit
  /// sign-out; a user who signs out re-enrolls after their next
  /// email/password login.
  ///
  /// `disableBiometricLogin()` is wrapped in its own try/catch: a
  /// flutter_secure_storage failure (a real Android Keystore /
  /// EncryptedSharedPreferences failure mode) must never block the actual
  /// sign-out below. The token about to be revoked server-side is dead
  /// either way, and `signInWithBiometrics()`'s own failure path clears any
  /// leftover token the next time it's used.
  Future<void> signOut() async {
    try {
      await disableBiometricLogin();
    } catch (_) {
      // See doc comment above -- a storage failure here must not prevent
      // the sign-out call below from running.
    }
    await _client.auth.signOut();
  }

  /// `redirectTo` must be a custom-scheme URL, not a bare '/reset-password'
  /// in-app route -- this link is opened by the OS from the user's email
  /// client, outside the Flutter app entirely, so it needs something the
  /// OS can route back to this app with (registered in AndroidManifest.xml
  /// and ios/Runner/Info.plist). It must also be added to this Supabase
  /// project's Authentication -> URL Configuration -> Redirect URLs
  /// allowlist in the dashboard, or GoTrue rejects it before ever sending
  /// the email.
  Future<void> resetPasswordForEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'renly://reset-password-callback',
    );
  }

  /// Called from ResetPasswordScreen once the recovery-session user (opened
  /// via the emailed reset link) has chosen a new password.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<bool> isBiometricAvailable() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final supported = await _localAuth.isDeviceSupported();
    return canCheck && supported;
  }

  /// Confirms the user's biometric identity, then stores the CURRENT
  /// session's refresh token. The constructor's `onAuthStateChange`
  /// listener keeps that stored copy fresh from here on. Cleared by
  /// `signOut()` -- see its doc comment for why surviving sign-out was
  /// never actually achievable.
  ///
  /// The null-refreshToken guard is load-bearing: `Session.refreshToken`
  /// is `String?`, and `FlutterSecureStorage.write` treats a null value as
  /// a DELETE, so writing it unguarded would silently no-op the enrollment
  /// (leaving biometric "enabled" in the UI with nothing stored).
  Future<void> enableBiometricLogin({required String localizedReason}) async {
    final authenticated = await _localAuth.authenticate(localizedReason: localizedReason);
    if (!authenticated) {
      throw StateError('Biometric authentication was not completed.');
    }
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('No active session to enable biometric login for.');
    }
    final refreshToken = session.refreshToken;
    if (refreshToken == null) {
      throw StateError('Current session has no refresh token to store.');
    }
    await _secureStorage.write(key: _biometricTokenKey, value: refreshToken);
  }

  Future<void> disableBiometricLogin() {
    return _secureStorage.delete(key: _biometricTokenKey);
  }

  Future<bool> hasBiometricLoginEnabled() {
    return _secureStorage.containsKey(key: _biometricTokenKey);
  }

  /// Restores the session from the stored refresh token after a successful
  /// biometric check, then IMMEDIATELY re-stores the new refresh token
  /// `setSession()`'s own response carries -- Supabase rotates the token on
  /// this call too, so without this the very next biometric attempt would
  /// present an already-consumed token and fail ("works once, then dies").
  /// This overlaps with the constructor's `onAuthStateChange` listener on
  /// purpose: the listener is the general safety net, this is the direct,
  /// ordering-independent write for the one path that matters most. Both
  /// are kept deliberately.
  ///
  /// If the stored token itself is invalid/expired (revoked server-side,
  /// or rotated elsewhere while this device was offline), clears it so
  /// `hasBiometricLoginEnabled()` -> false and the Biometric button
  /// disappears -- rather than leaving a permanently-broken button behind.
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
      final response = await _client.auth.setSession(token);
      final newRefreshToken = response.session?.refreshToken;
      if (newRefreshToken != null) {
        await _secureStorage.write(key: _biometricTokenKey, value: newRefreshToken);
      }
      return response;
    } catch (e) {
      await _secureStorage.delete(key: _biometricTokenKey);
      rethrow;
    }
  }

  /// Returns null if the caller has an auth session but no `negotiator`
  /// row yet (e.g. the app was killed between signUp() and Task 8's
  /// insertNegotiator() call during a previous attempt).
  Future<Negotiator?> fetchOwnNegotiator(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('negotiator_id, full_name, verification_status')
        .eq('negotiator_id', negotiatorId)
        .maybeSingle();
    if (row == null) return null;
    return Negotiator.fromJson(row);
  }
}

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/negotiator.dart';

/// The only file in this app that talks to Supabase for auth/registration.
/// Screens call these methods; nothing else touches `SupabaseClient` for
/// this feature.
class AuthRepository {
  AuthRepository(this._client);

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

  Future<void> insertNegotiator({
    required String negotiatorId,
    required String fullName,
    required String icNumber,
    required String phoneNumber,
  }) {
    return _client.from('negotiator').insert({
      'negotiator_id': negotiatorId,
      'full_name': fullName,
      'ic_number': icNumber,
      'phone_number': phoneNumber,
    });
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

  Future<void> insertVerificationRecord({
    required String negotiatorId,
    required String tagPhotoUrl,
  }) {
    return _client.from('verification_record').insert({
      'negotiator_id': negotiatorId,
      'tag_photo_url': tagPhotoUrl,
    });
  }

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  Future<void> resetPasswordForEmail(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

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

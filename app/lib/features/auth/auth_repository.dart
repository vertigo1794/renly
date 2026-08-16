import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/negotiator.dart';

/// The only file in this app that talks to Supabase for auth/registration.
/// Screens call these methods; nothing else touches `SupabaseClient` for
/// this feature.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

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

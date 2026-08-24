import 'package:supabase_flutter/supabase_flutter.dart';

/// The only file in this app that writes fcm_device_token directly.
class FcmTokenRepository {
  FcmTokenRepository(this._client);

  final SupabaseClient _client;

  Future<void> registerToken({required String negotiatorId, required String token}) async {
    // ignoreDuplicates: true turns a conflict into ON CONFLICT DO NOTHING.
    // migration 0016_fcm_device_token.sql deliberately grants no UPDATE
    // policy on this table (a token is either current/present or
    // stale/deleted, never edited in place) -- the Supabase client default
    // of ignoreDuplicates: false issues ON CONFLICT DO UPDATE, which would
    // hit permission-denied on every re-registration of an unchanged token
    // (i.e. every app launch after the first, since FCM tokens rarely
    // rotate).
    await _client.from('fcm_device_token').upsert(
      {'negotiator_id': negotiatorId, 'token': token},
      onConflict: 'negotiator_id,token',
      ignoreDuplicates: true,
    );
  }
}

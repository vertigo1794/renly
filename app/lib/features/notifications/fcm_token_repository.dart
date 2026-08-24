import 'package:supabase_flutter/supabase_flutter.dart';

/// The only file in this app that writes fcm_device_token directly.
class FcmTokenRepository {
  FcmTokenRepository(this._client);

  final SupabaseClient _client;

  Future<void> registerToken({required String negotiatorId, required String token}) async {
    await _client.from('fcm_device_token').upsert(
      {'negotiator_id': negotiatorId, 'token': token},
      onConflict: 'negotiator_id,token',
    );
  }
}

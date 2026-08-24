import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/push_payload.dart';

/// Calls the send-push-notification Edge Function. Never throws to a
/// caller that treats push delivery as best-effort (Tasks 5-7) -- those
/// callers wrap this in their own try/catch and swallow failures, since a
/// push failing must never undo or error out an already-successful
/// primary action (a new match, a sent request, a sent message).
class PushNotificationRepository {
  PushNotificationRepository(this._client);

  final SupabaseClient _client;

  Future<void> sendPushNotification(PushPayload payload) async {
    await _client.functions.invoke('send-push-notification', body: payload.toJson());
  }
}

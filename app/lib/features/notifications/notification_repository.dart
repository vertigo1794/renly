import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/app_notification.dart';

/// The only file in this app that talks to Supabase for the in-app
/// Notification Center. Rows are written exclusively by the
/// send-push-notification Edge Function's service-role client -- this
/// repository only ever reads and marks-read, matching the `notification`
/// table's RLS (select + update(read_at) only, no insert for authenticated).
class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> fetchNotifications(String recipientId) async {
    final rows = await _client
        .from('notification')
        .select()
        .eq('recipient_id', recipientId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List).map((row) => AppNotification.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<void> markRead(String notificationId) async {
    await _client
        .from('notification')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('notification_id', notificationId);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/identity_info.dart';
import 'models/notification_preferences.dart';

/// The only file in this app that talks to Supabase for the settings
/// feature. Composes nothing -- every method is a direct read/write on
/// `negotiator` or a call into Supabase Auth, same shallow shape as
/// ProfileRepository.
class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  Future<NotificationPreferences> fetchNotificationPreferences(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('notify_match, notify_message, notify_cobroke_request')
        .eq('negotiator_id', negotiatorId)
        .single();
    return NotificationPreferences.fromJson(row);
  }

  Future<void> updateNotificationPreferences({
    required String negotiatorId,
    required bool notifyMatch,
    required bool notifyMessage,
    required bool notifyCobrokeRequest,
  }) {
    return _client.from('negotiator').update({
      'notify_match': notifyMatch,
      'notify_message': notifyMessage,
      'notify_cobroke_request': notifyCobrokeRequest,
    }).eq('negotiator_id', negotiatorId);
  }

  /// Deliberately separate from ProfileRepository.fetchMyProfile, which
  /// excludes ic_number/phone_number to avoid pulling PII into memory on
  /// every Profile screen view. This query only runs when the Account
  /// settings screen is opened.
  Future<IdentityInfo> fetchIdentityInfo(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('ic_number, phone_number, ren_number')
        .eq('negotiator_id', negotiatorId)
        .single();
    return IdentityInfo.fromJson(row);
  }

  /// No current-password argument -- Supabase Auth's updateUser call has
  /// no such parameter, since it operates on the already-authenticated
  /// session, not a re-authentication flow.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}

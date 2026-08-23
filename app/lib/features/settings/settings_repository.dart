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

  /// Writes only the fields that are non-null -- a genuine partial update,
  /// not a full-row overwrite. This is load-bearing: the caller only ever
  /// has a fresh value for the single switch that was just tapped, and
  /// sending stale values for the other two columns (read from a
  /// last-rendered snapshot) can silently clobber a concurrent write to
  /// this same row. See NotificationSettingsScreen._toggle.
  Future<void> updateNotificationPreferences({
    required String negotiatorId,
    bool? notifyMatch,
    bool? notifyMessage,
    bool? notifyCobrokeRequest,
  }) {
    final payload = <String, dynamic>{
      'notify_match': ?notifyMatch,
      'notify_message': ?notifyMessage,
      'notify_cobroke_request': ?notifyCobrokeRequest,
    };
    return _client.from('negotiator').update(payload).eq('negotiator_id', negotiatorId);
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

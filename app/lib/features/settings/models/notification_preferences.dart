/// Real, DB-persisted notification preference flags -- functionally inert
/// today since this app has no push notification delivery (no FCM wired
/// in anywhere). Kept as genuine columns rather than a client-only toggle
/// so nothing needs rebuilding once push delivery exists.
class NotificationPreferences {
  final bool notifyMatch;
  final bool notifyMessage;
  final bool notifyCobrokeRequest;

  const NotificationPreferences({
    required this.notifyMatch,
    required this.notifyMessage,
    required this.notifyCobrokeRequest,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      notifyMatch: json['notify_match'] as bool,
      notifyMessage: json['notify_message'] as bool,
      notifyCobrokeRequest: json['notify_cobroke_request'] as bool,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/settings/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences.fromJson', () {
    test('parses all three flags', () {
      final prefs = NotificationPreferences.fromJson({
        'notify_match': true,
        'notify_message': false,
        'notify_cobroke_request': true,
      });

      expect(prefs.notifyMatch, isTrue);
      expect(prefs.notifyMessage, isFalse);
      expect(prefs.notifyCobrokeRequest, isTrue);
    });
  });
}

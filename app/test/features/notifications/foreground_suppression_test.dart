import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/foreground_suppression.dart';

void main() {
  group('shouldSuppressForegroundBanner', () {
    test('suppresses a message push when already viewing that exact chat', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: '/messages/REQ1',
        data: {'request_id': 'REQ1'},
      );
      expect(suppressed, isTrue);
    });

    test('does not suppress a message push for a different chat', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: '/messages/REQ2',
        data: {'request_id': 'REQ1'},
      );
      expect(suppressed, isFalse);
    });

    test('never suppresses match or cobroke_request pushes -- no Realtime screen backs them', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'match',
        currentRouteLocation: '/property/L1/matches',
        data: {'listing_id': 'L1'},
      );
      expect(suppressed, isFalse);
    });

    test('does not suppress when current route is unknown (null)', () {
      final suppressed = shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: null,
        data: {'request_id': 'REQ1'},
      );
      expect(suppressed, isFalse);
    });
  });
}

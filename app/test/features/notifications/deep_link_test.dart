import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/deep_link.dart';

void main() {
  group('deepLinkRouteFor', () {
    test('match category, owner_side listing routes to property matches', () {
      final route = deepLinkRouteFor('match', {'owner_side': 'listing', 'listing_id': 'L1'});
      expect(route, '/property/L1/matches');
    });

    test('match category, owner_side requirement routes to requirement-board matches', () {
      final route = deepLinkRouteFor('match', {'owner_side': 'requirement', 'requirement_id': 'R1'});
      expect(route, '/requirement-board/R1/matches');
    });

    test('cobroke_request category routes to my-requests', () {
      final route = deepLinkRouteFor('cobroke_request', {});
      expect(route, '/my-requests');
    });

    test('message category routes to messages/:requestId', () {
      final route = deepLinkRouteFor('message', {'request_id': 'REQ1'});
      expect(route, '/messages/REQ1');
    });

    test('unknown category falls back to /home', () {
      final route = deepLinkRouteFor('unknown', {});
      expect(route, '/home');
    });
  });
}

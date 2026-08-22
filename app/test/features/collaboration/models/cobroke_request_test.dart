import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';

void main() {
  group('CobrokeRequest.fromJson', () {
    test('parses a full row', () {
      final request = CobrokeRequest.fromJson({
        'request_id': 'req-1',
        'match_id': 'm-1',
        'initiator_id': 'n-1',
        'status': 'pending',
        'created_at': '2026-08-23T10:00:00.000Z',
      });

      expect(request.requestId, 'req-1');
      expect(request.matchId, 'm-1');
      expect(request.initiatorId, 'n-1');
      expect(request.status, 'pending');
      expect(request.createdAt, DateTime.parse('2026-08-23T10:00:00.000Z'));
    });
  });
}

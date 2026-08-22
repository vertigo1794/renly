import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/message.dart';

void main() {
  group('Message.fromJson', () {
    test('parses a full row', () {
      final message = Message.fromJson({
        'message_id': 'msg-1',
        'request_id': 'req-1',
        'sender_id': 'n-1',
        'body': 'Hi, interested to co-broke.',
        'sent_at': '2026-08-24T10:00:00.000Z',
      });

      expect(message.messageId, 'msg-1');
      expect(message.requestId, 'req-1');
      expect(message.senderId, 'n-1');
      expect(message.body, 'Hi, interested to co-broke.');
      expect(message.sentAt, DateTime.parse('2026-08-24T10:00:00.000Z'));
    });
  });
}

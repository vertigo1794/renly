import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/auth/models/negotiator.dart';

void main() {
  group('Negotiator.fromJson', () {
    test('parses a full row', () {
      final negotiator = Negotiator.fromJson({
        'negotiator_id': 'abc-123',
        'full_name': 'Aiman Yusof',
        'verification_status': 'pending',
      });

      expect(negotiator.negotiatorId, 'abc-123');
      expect(negotiator.fullName, 'Aiman Yusof');
      expect(negotiator.verificationStatus, 'pending');
    });
  });
}

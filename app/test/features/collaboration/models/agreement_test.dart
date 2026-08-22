// app/test/features/collaboration/models/agreement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/agreement.dart';

void main() {
  group('Agreement.fromJson', () {
    test('parses a pending row with null terms and accepted_at', () {
      final agreement = Agreement.fromJson({
        'agreement_id': 'agr-1',
        'request_id': 'req-1',
        'initiator_id': 'n-1',
        'split_initiator': 60,
        'split_counterparty': 40,
        'terms': null,
        'status': 'pending',
        'accepted_at': null,
        'created_at': '2026-08-24T10:00:00.000Z',
      });

      expect(agreement.agreementId, 'agr-1');
      expect(agreement.requestId, 'req-1');
      expect(agreement.initiatorId, 'n-1');
      expect(agreement.splitInitiator, 60.0);
      expect(agreement.splitCounterparty, 40.0);
      expect(agreement.terms, isNull);
      expect(agreement.status, 'pending');
      expect(agreement.acceptedAt, isNull);
      expect(agreement.createdAt, DateTime.parse('2026-08-24T10:00:00.000Z'));
    });

    test('parses an accepted row with terms and accepted_at', () {
      final agreement = Agreement.fromJson({
        'agreement_id': 'agr-2',
        'request_id': 'req-2',
        'initiator_id': 'n-2',
        'split_initiator': 55.5,
        'split_counterparty': 44.5,
        'terms': 'Standard split after marketing fee',
        'status': 'accepted',
        'accepted_at': '2026-08-24T12:00:00.000Z',
        'created_at': '2026-08-24T10:00:00.000Z',
      });

      expect(agreement.splitInitiator, 55.5);
      expect(agreement.splitCounterparty, 44.5);
      expect(agreement.terms, 'Standard split after marketing fee');
      expect(agreement.status, 'accepted');
      expect(agreement.acceptedAt, DateTime.parse('2026-08-24T12:00:00.000Z'));
    });
  });
}

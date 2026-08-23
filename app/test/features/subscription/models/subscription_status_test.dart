// app/test/features/subscription/models/subscription_status_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/subscription/models/subscription_status.dart';

void main() {
  group('SubscriptionStatus.fromJson', () {
    test('parses a professional subscription with all fields present', () {
      final status = SubscriptionStatus.fromJson({
        'subscription_tier': 'professional',
        'subscription_status': 'active',
        'current_period_end': '2026-09-24T10:00:00.000Z',
      });

      expect(status.tier, 'professional');
      expect(status.status, 'active');
      expect(status.currentPeriodEnd, DateTime.parse('2026-09-24T10:00:00.000Z'));
    });

    test('parses a free negotiator with null subscription fields', () {
      final status = SubscriptionStatus.fromJson({
        'subscription_tier': 'free',
        'subscription_status': null,
        'current_period_end': null,
      });

      expect(status.tier, 'free');
      expect(status.status, isNull);
      expect(status.currentPeriodEnd, isNull);
    });
  });
}

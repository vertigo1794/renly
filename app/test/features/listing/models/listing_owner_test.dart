// app/test/features/listing/models/listing_owner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing_owner.dart';

void main() {
  group('ListingOwner.fromJson', () {
    test('parses verification_status when present', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
        'agency_name': 'ESP Global',
        'verification_status': 'approved',
      });

      expect(owner.verificationStatus, 'approved');
    });

    test('verification_status is null when absent, never a fabricated fallback', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
      });

      expect(owner.verificationStatus, isNull);
    });
  });
}

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

    test('parses avatar_url and is_online when present', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
        'avatar_url': 'https://example.test/avatar.jpg',
        'is_online': true,
      });

      expect(owner.avatarUrl, 'https://example.test/avatar.jpg');
      expect(owner.isOnline, isTrue);
    });

    test('avatarUrl is null and isOnline is false when absent, never fabricated', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
      });

      expect(owner.avatarUrl, isNull);
      expect(owner.isOnline, isFalse);
    });
  });
}

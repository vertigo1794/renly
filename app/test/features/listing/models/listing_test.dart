// app/test/features/listing/models/listing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';

void main() {
  group('Listing.fromJson', () {
    test('parses a full row', () {
      final listing = Listing.fromJson({
        'listing_id': 'l-1',
        'negotiator_id': 'n-1',
        'title': 'The Vertex Residency',
        'description': 'A modern apartment.',
        'property_type': 'apartment',
        'transaction_type': 'sale',
        'state': 'Selangor',
        'area': 'Petaling Jaya',
        'price': 1250000,
        'bedrooms': 3,
        'bathrooms': 2,
        'photo_urls': ['n-1/l-1/0.jpg', 'n-1/l-1/1.jpg'],
        'status': 'active',
        'created_at': '2024-01-01T00:00:00Z',
      });

      expect(listing.listingId, 'l-1');
      expect(listing.negotiatorId, 'n-1');
      expect(listing.title, 'The Vertex Residency');
      expect(listing.price, 1250000.0);
      expect(listing.bedrooms, 3);
      expect(listing.bathrooms, 2);
      expect(listing.photoUrls, ['n-1/l-1/0.jpg', 'n-1/l-1/1.jpg']);
      expect(listing.status, 'active');
      expect(listing.createdAt, DateTime.parse('2024-01-01T00:00:00Z'));
    });

    test('handles null bedrooms/bathrooms and empty photo_urls', () {
      final listing = Listing.fromJson({
        'listing_id': 'l-2',
        'negotiator_id': 'n-1',
        'title': 'Empty Land Plot',
        'description': 'Vacant land.',
        'property_type': 'land',
        'transaction_type': 'sale',
        'state': 'Johor',
        'area': 'Iskandar Puteri',
        'price': 500000,
        'bedrooms': null,
        'bathrooms': null,
        'photo_urls': null,
        'status': 'active',
        'created_at': '2024-01-01T00:00:00Z',
      });

      expect(listing.bedrooms, isNull);
      expect(listing.bathrooms, isNull);
      expect(listing.photoUrls, isEmpty);
    });

    test('populated new fields round-trip with correct types', () {
      final json = {
        'listing_id': 'l-1',
        'negotiator_id': 'n-1',
        'title': 't',
        'description': 'd',
        'property_type': 'apartment',
        'transaction_type': 'sale',
        'state': 'Selangor',
        'area': 'Petaling Jaya',
        'price': 500000,
        'photo_urls': <String>[],
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'maintenance_fee_myr': 580,
        'tenure': 'freehold',
        'parking_bays': 2,
        'floor_level': 38,
        'furnishing_status': 'furnished',
        'keys_on_hand': true,
        'protected_co_broke_reg': true,
        'total_agency_commission_percent': 3,
      };

      final listing = Listing.fromJson(json);

      expect(listing.maintenanceFeeMyr, 580.0);
      expect(listing.maintenanceFeeMyr, isA<double>());
      expect(listing.tenure, 'freehold');
      expect(listing.parkingBays, 2);
      expect(listing.floorLevel, 38);
      expect(listing.furnishingStatus, 'furnished');
      expect(listing.keysOnHand, true);
      expect(listing.protectedCoBrokeReg, true);
      expect(listing.totalAgencyCommissionPercent, 3.0);
      expect(listing.totalAgencyCommissionPercent, isA<double>());
    });

    test('omitted new fields default to null/false, never a fabricated fallback', () {
      final json = {
        'listing_id': 'l-1',
        'negotiator_id': 'n-1',
        'title': 't',
        'description': 'd',
        'property_type': 'apartment',
        'transaction_type': 'sale',
        'state': 'Selangor',
        'area': 'Petaling Jaya',
        'price': 500000,
        'photo_urls': <String>[],
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final listing = Listing.fromJson(json);

      expect(listing.maintenanceFeeMyr, isNull);
      expect(listing.tenure, isNull);
      expect(listing.parkingBays, isNull);
      expect(listing.floorLevel, isNull);
      expect(listing.furnishingStatus, isNull);
      expect(listing.keysOnHand, false);
      expect(listing.protectedCoBrokeReg, false);
      expect(listing.totalAgencyCommissionPercent, isNull);
    });
  });
}

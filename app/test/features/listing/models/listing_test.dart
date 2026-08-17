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
      });

      expect(listing.listingId, 'l-1');
      expect(listing.negotiatorId, 'n-1');
      expect(listing.title, 'The Vertex Residency');
      expect(listing.price, 1250000.0);
      expect(listing.bedrooms, 3);
      expect(listing.bathrooms, 2);
      expect(listing.photoUrls, ['n-1/l-1/0.jpg', 'n-1/l-1/1.jpg']);
      expect(listing.status, 'active');
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
      });

      expect(listing.bedrooms, isNull);
      expect(listing.bathrooms, isNull);
      expect(listing.photoUrls, isEmpty);
    });
  });
}

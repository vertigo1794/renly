// app/test/features/listing/listing_status_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/listing_status_filter.dart';
import 'package:renly/features/listing/models/listing.dart';

Listing _listing(String id, String status) {
  return Listing(
    listingId: id,
    negotiatorId: 'n-1',
    title: 'Test $id',
    description: 'desc',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'PJ',
    price: 100000,
    photoUrls: const [],
    status: status,
  );
}

void main() {
  group('ListingStatusFilter.byStatus', () {
    test('returns only listings matching the given status', () {
      final listings = [_listing('1', 'active'), _listing('2', 'sold'), _listing('3', 'active')];
      final result = ListingStatusFilter.byStatus(listings, 'active');
      expect(result.map((l) => l.listingId), ['1', '3']);
    });

    test('returns empty list when nothing matches', () {
      final listings = [_listing('1', 'active')];
      expect(ListingStatusFilter.byStatus(listings, 'withdrawn'), isEmpty);
    });
  });
}

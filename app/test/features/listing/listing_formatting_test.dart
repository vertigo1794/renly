// app/test/features/listing/listing_formatting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/listing_formatting.dart';

void main() {
  group('ListingFormatting.formatPrice', () {
    test('formats a sale price with thousands separators', () {
      expect(ListingFormatting.formatPrice(1250000, 'sale'), 'RM 1,250,000');
    });

    test('formats a rental price with /mo suffix', () {
      expect(ListingFormatting.formatPrice(12000, 'rent'), 'RM 12,000 /mo');
    });

    test('formats a price under 1000 with no separator', () {
      expect(ListingFormatting.formatPrice(500, 'sale'), 'RM 500');
    });

    test('formats a price of exactly 1000', () {
      expect(ListingFormatting.formatPrice(1000, 'sale'), 'RM 1,000');
    });
  });
}

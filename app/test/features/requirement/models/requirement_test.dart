// app/test/features/requirement/models/requirement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/requirement/models/requirement.dart';

void main() {
  group('Requirement.fromJson', () {
    test('parses a full row', () {
      final requirement = Requirement.fromJson({
        'requirement_id': 'r-1',
        'negotiator_id': 'n-1',
        'property_type': 'apartment',
        'transaction_type': 'sale',
        'state': 'Selangor',
        'area': 'Petaling Jaya',
        'budget_min': 300000,
        'budget_max': 500000,
        'bedrooms': 3,
        'photo_urls': ['n-1/r-1/0.jpg'],
        'status': 'open',
      });

      expect(requirement.requirementId, 'r-1');
      expect(requirement.negotiatorId, 'n-1');
      expect(requirement.propertyType, 'apartment');
      expect(requirement.transactionType, 'sale');
      expect(requirement.state, 'Selangor');
      expect(requirement.area, 'Petaling Jaya');
      expect(requirement.budgetMin, 300000.0);
      expect(requirement.budgetMax, 500000.0);
      expect(requirement.bedrooms, 3);
      expect(requirement.photoUrls, ['n-1/r-1/0.jpg']);
      expect(requirement.status, 'open');
    });

    test('handles null bedrooms and empty photo_urls', () {
      final requirement = Requirement.fromJson({
        'requirement_id': 'r-2',
        'negotiator_id': 'n-1',
        'property_type': 'land',
        'transaction_type': 'sale',
        'state': 'Johor',
        'area': 'Iskandar Puteri',
        'budget_min': 100000,
        'budget_max': 200000,
        'bedrooms': null,
        'photo_urls': null,
        'status': 'open',
      });

      expect(requirement.bedrooms, isNull);
      expect(requirement.photoUrls, isEmpty);
    });
  });
}

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
        'bathrooms_min': 2,
        'built_up_sqft_min': 900,
        // Passed as an int (as a real Postgres numeric column would come
        // back over the wire in some cases) to exercise the num -> double
        // coercion, same as budget_min/budget_max above.
        'desired_commission_split_percent': 50,
        'loan_ready': true,
        'urgent_viewing_required': true,
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
      expect(requirement.bathroomsMin, 2);
      expect(requirement.builtUpSqftMin, 900);
      expect(requirement.desiredCommissionSplitPercent, 50.0);
      expect(requirement.desiredCommissionSplitPercent, isA<double>());
      expect(requirement.loanReady, isTrue);
      expect(requirement.urgentViewingRequired, isTrue);
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

    test('defaults bathroomsMin/builtUpSqftMin/desiredCommissionSplitPercent to null and loanReady/urgentViewingRequired to false when the JSON keys are entirely absent', () {
      final requirement = Requirement.fromJson({
        'requirement_id': 'r-3',
        'negotiator_id': 'n-1',
        'property_type': 'house',
        'transaction_type': 'rent',
        'state': 'Penang',
        'area': 'George Town',
        'budget_min': 1500,
        'budget_max': 2500,
        'bedrooms': 2,
        'photo_urls': [],
        'status': 'open',
        // bathrooms_min, built_up_sqft_min, desired_commission_split_percent,
        // loan_ready, urgent_viewing_required are all deliberately omitted.
      });

      expect(requirement.bathroomsMin, isNull);
      expect(requirement.builtUpSqftMin, isNull);
      expect(requirement.desiredCommissionSplitPercent, isNull);
      expect(requirement.loanReady, isFalse);
      expect(requirement.urgentViewingRequired, isFalse);
    });
  });
}

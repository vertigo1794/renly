import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/matching/matching_engine.dart';
import 'package:renly/features/requirement/models/requirement.dart';

final _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  bedrooms: 3,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

const _requirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  bedrooms: 3,
  photoUrls: [],
  status: 'open',
);

void main() {
  group('MatchingEngine.score', () {
    test('full match on every dimension scores 100', () {
      expect(MatchingEngine.score(_listing, _requirement), 100);
    });

    test('transaction type mismatch disqualifies the pair', () {
      final requirement = Requirement(
        requirementId: _requirement.requirementId,
        negotiatorId: _requirement.negotiatorId,
        propertyType: _requirement.propertyType,
        transactionType: 'rent',
        state: _requirement.state,
        area: _requirement.area,
        budgetMin: _requirement.budgetMin,
        budgetMax: _requirement.budgetMax,
        bedrooms: _requirement.bedrooms,
        photoUrls: _requirement.photoUrls,
        status: _requirement.status,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('state mismatch disqualifies the pair', () {
      final requirement = Requirement(
        requirementId: _requirement.requirementId,
        negotiatorId: _requirement.negotiatorId,
        propertyType: _requirement.propertyType,
        transactionType: _requirement.transactionType,
        state: 'Johor',
        area: _requirement.area,
        budgetMin: _requirement.budgetMin,
        budgetMax: _requirement.budgetMax,
        bedrooms: _requirement.bedrooms,
        photoUrls: _requirement.photoUrls,
        status: _requirement.status,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('area mismatch loses the 30 location points', () {
      final requirement = Requirement(
        requirementId: _requirement.requirementId,
        negotiatorId: _requirement.negotiatorId,
        propertyType: _requirement.propertyType,
        transactionType: _requirement.transactionType,
        state: _requirement.state,
        area: 'Shah Alam',
        budgetMin: _requirement.budgetMin,
        budgetMax: _requirement.budgetMax,
        bedrooms: _requirement.bedrooms,
        photoUrls: _requirement.photoUrls,
        status: _requirement.status,
      );
      expect(MatchingEngine.score(_listing, requirement), 70);
    });

    test('price 5 percent over max gets half the graduated band', () {
      final listing = Listing(
        listingId: 'l-2',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 525000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      expect(MatchingEngine.score(listing, _requirement), 83);
    });

    test('price beyond 10 percent over max scores zero for price', () {
      final listing = Listing(
        listingId: 'l-3',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 600000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      expect(MatchingEngine.score(listing, _requirement), 65);
    });

    test('price below budget minimum still scores full price weight', () {
      final listing = Listing(
        listingId: 'l-4',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 250000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      expect(MatchingEngine.score(listing, _requirement), 100);
    });

    test('unspecified requirement bedrooms scores full bedroom weight', () {
      const requirement = Requirement(
        requirementId: 'r-2',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        photoUrls: [],
        status: 'open',
      );
      expect(MatchingEngine.score(_listing, requirement), 100);
    });

    test('mismatched bedroom count scores zero for bedrooms', () {
      const requirement = Requirement(
        requirementId: 'r-3',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 2,
        photoUrls: [],
        status: 'open',
      );
      expect(MatchingEngine.score(_listing, requirement), 90);
    });

    test('listing meeting the requirement\'s bathroomsMin still scores normally', () {
      final listing = Listing(
        listingId: 'l-5',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        bathrooms: 2,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-4',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        bathroomsMin: 2,
      );
      expect(MatchingEngine.score(listing, requirement), 100);
    });

    test('listing below the requirement\'s bathroomsMin is disqualified', () {
      final listing = Listing(
        listingId: 'l-6',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        bathrooms: 1,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-5',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        bathroomsMin: 2,
      );
      expect(MatchingEngine.score(listing, requirement), isNull);
    });

    test('listing with unset bathrooms is disqualified when requirement sets a minimum', () {
      const requirement = Requirement(
        requirementId: 'r-6',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        bathroomsMin: 2,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('requirement with no bathroomsMin never filters on bathrooms', () {
      final listing = Listing(
        listingId: 'l-7',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      expect(MatchingEngine.score(listing, _requirement), 100);
    });

    test('listing meeting the requirement\'s builtUpSqftMin still scores normally', () {
      final listing = Listing(
        listingId: 'l-8',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        builtUpSqft: 1200,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-7',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        builtUpSqftMin: 1000,
      );
      expect(MatchingEngine.score(listing, requirement), 100);
    });

    test('listing below the requirement\'s builtUpSqftMin is disqualified', () {
      final listing = Listing(
        listingId: 'l-9',
        negotiatorId: 'n-1',
        title: 't',
        description: 'd',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        price: 400000,
        bedrooms: 3,
        builtUpSqft: 800,
        photoUrls: [],
        status: 'active',
        createdAt: DateTime(2024, 1, 1),
      );
      const requirement = Requirement(
        requirementId: 'r-8',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        builtUpSqftMin: 1000,
      );
      expect(MatchingEngine.score(listing, requirement), isNull);
    });

    test('listing with unset builtUpSqft is disqualified when requirement sets a minimum', () {
      const requirement = Requirement(
        requirementId: 'r-9',
        negotiatorId: 'n-2',
        propertyType: 'apartment',
        transactionType: 'sale',
        state: 'Selangor',
        area: 'Petaling Jaya',
        budgetMin: 300000,
        budgetMax: 500000,
        bedrooms: 3,
        photoUrls: [],
        status: 'open',
        builtUpSqftMin: 1000,
      );
      expect(MatchingEngine.score(_listing, requirement), isNull);
    });

    test('requirement with no builtUpSqftMin never filters on built-up size', () {
      expect(MatchingEngine.score(_listing, _requirement), 100);
    });

    test('qualifyingThreshold is 40', () {
      expect(MatchingEngine.qualifyingThreshold, 40);
    });
  });
}

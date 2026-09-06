import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/matching/live_match_preview.dart';
import 'package:renly/features/requirement/models/requirement.dart';

Listing _listing(String id, {double price = 400000, String area = 'Petaling Jaya', String title = 't'}) {
  return Listing(
    listingId: id,
    negotiatorId: 'n-owner',
    title: title,
    description: 'd',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: area,
    price: price,
    bedrooms: 3,
    photoUrls: const [],
    status: 'active',
    createdAt: DateTime(2024, 1, 1),
  );
}

const _draftRequirement = Requirement(
  requirementId: 'preview',
  negotiatorId: 'n-buyer',
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
  group('LiveMatchPreview.forRequirement', () {
    test('counts only candidates at or above the qualifying threshold', () {
      // l-2 is disqualified by two stacked deductions (area mismatch loses
      // the 30 location points, and a price far enough over budgetMax
      // zeroes the 35 price points), landing at 35 -- below the 40
      // qualifyingThreshold. A single mismatched dimension is never enough
      // on its own: see matching_engine_test.dart's "area mismatch loses
      // the 30 location points" case, which score 70 alone.
      final candidates = [
        _listing('l-1', title: 'The Vertex Residency'),
        _listing('l-2', area: 'Shah Alam', price: 600000, title: 'Mismatched Area Unit'),
      ];

      final result = LiveMatchPreview.forRequirement(_draftRequirement, candidates);

      expect(result.matchCount, 1);
      expect(result.topMatchLabel, 'The Vertex Residency');
      expect(result.topMatchScore, 100);
    });

    test('zero qualifying candidates returns a zero-count result with no top match', () {
      // Same stacked-deduction reasoning as above: area mismatch alone
      // (score 70) would still qualify, so price is also pushed over
      // budgetMax * 1.10 to land the total at 35, below the threshold.
      final candidates = [_listing('l-1', area: 'Shah Alam', price: 600000)];

      final result = LiveMatchPreview.forRequirement(_draftRequirement, candidates);

      expect(result.matchCount, 0);
      expect(result.topMatchLabel, isNull);
      expect(result.topMatchScore, isNull);
    });

    test('picks the highest-scoring candidate as the top match', () {
      final candidates = [
        _listing('l-1', price: 600000, title: 'Over Budget Unit'),
        _listing('l-2', price: 400000, title: 'Exact Budget Unit'),
      ];

      final result = LiveMatchPreview.forRequirement(_draftRequirement, candidates);

      expect(result.matchCount, 2);
      expect(result.topMatchLabel, 'Exact Budget Unit');
      expect(result.topMatchScore, 100);
    });
  });

  group('LiveMatchPreview.forListing', () {
    test('counts only candidates at or above the qualifying threshold', () {
      final draftListing = _listing('preview', title: 'Draft Listing');
      const requirements = [
        Requirement(
          requirementId: 'r-1',
          negotiatorId: 'n-buyer-1',
          propertyType: 'apartment',
          transactionType: 'sale',
          state: 'Selangor',
          area: 'Petaling Jaya',
          budgetMin: 300000,
          budgetMax: 500000,
          bedrooms: 3,
          photoUrls: [],
          status: 'open',
        ),
        Requirement(
          requirementId: 'r-2',
          negotiatorId: 'n-buyer-2',
          propertyType: 'apartment',
          transactionType: 'sale',
          state: 'Johor',
          area: 'Johor Bahru',
          budgetMin: 300000,
          budgetMax: 500000,
          bedrooms: 3,
          photoUrls: [],
          status: 'open',
        ),
      ];

      final result = LiveMatchPreview.forListing(draftListing, requirements);

      expect(result.matchCount, 1);
      expect(result.topMatchLabel, 'apartment buyer in Petaling Jaya');
      expect(result.topMatchScore, 100);
    });

    test('zero qualifying candidates returns a zero-count result with no top match', () {
      // A single mismatched dimension (propertyType alone) still scores 75
      // (location 30 + price 35 + bedrooms 10) and would qualify, so this
      // stacks propertyType, area, and an out-of-band budget together to
      // land the total at 10 -- below the 40 qualifyingThreshold. See the
      // stacked-deduction note on the forRequirement tests above.
      final draftListing = _listing('preview');
      const requirements = [
        Requirement(
          requirementId: 'r-1',
          negotiatorId: 'n-buyer-1',
          propertyType: 'house',
          transactionType: 'sale',
          state: 'Selangor',
          area: 'Shah Alam',
          budgetMin: 100000,
          budgetMax: 200000,
          photoUrls: [],
          status: 'open',
        ),
      ];

      final result = LiveMatchPreview.forListing(draftListing, requirements);

      expect(result.matchCount, 0);
      expect(result.topMatchLabel, isNull);
      expect(result.topMatchScore, isNull);
    });
  });
}

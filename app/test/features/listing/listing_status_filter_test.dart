// app/test/features/listing/listing_status_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/listing/listing_status_filter.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

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
    createdAt: DateTime(2024, 1, 1),
  );
}

CobrokeRequestCandidate _pendingRequestFor(String listingId) {
  final listing = _listing(listingId, 'active');
  const requirement = Requirement(
    requirementId: 'r-1',
    negotiatorId: 'n-2',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'PJ',
    budgetMin: 100000,
    budgetMax: 200000,
    photoUrls: [],
    status: 'open',
  );
  const owner = ListingOwner(fullName: 'Owner', renNumber: '12345');
  return CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: 'req-$listingId',
      matchId: 'm-$listingId',
      initiatorId: 'n-2',
      status: 'pending',
      createdAt: DateTime(2026, 9, 6),
    ),
    match: MatchCandidate(
      matchId: 'm-$listingId',
      score: 90,
      listing: listing,
      requirement: requirement,
      listingOwner: owner,
      requirementOwner: owner,
    ),
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

  group('ListingStatusFilter.partition', () {
    test('splits active listings into Active vs Co-Broke in Review by pending requests', () {
      final listings = [_listing('1', 'active'), _listing('2', 'active')];
      final received = [_pendingRequestFor('2')];

      final result = ListingStatusFilter.partition(listings, received);

      expect(result.active.map((l) => l.listingId), ['1']);
      expect(result.coBrokeInReview.map((l) => l.listingId), ['2']);
      expect(result.closedSold, isEmpty);
    });

    test('groups sold and withdrawn together under closedSold', () {
      final listings = [_listing('1', 'sold'), _listing('2', 'withdrawn'), _listing('3', 'active')];

      final result = ListingStatusFilter.partition(listings, const []);

      expect(result.closedSold.map((l) => l.listingId).toSet(), {'1', '2'});
      expect(result.active.map((l) => l.listingId), ['3']);
    });

    test('a DECLINED request on a listing does not move it into coBrokeInReview', () {
      final listings = [_listing('1', 'active')];
      final declined = _pendingRequestFor('1');
      final declinedRequest = CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: declined.request.requestId,
          matchId: declined.request.matchId,
          initiatorId: declined.request.initiatorId,
          status: 'declined',
          createdAt: declined.request.createdAt,
        ),
        match: declined.match,
      );

      final result = ListingStatusFilter.partition(listings, [declinedRequest]);

      expect(result.active.map((l) => l.listingId), ['1']);
      expect(result.coBrokeInReview, isEmpty);
    });

    test('partition is mutually exclusive and sums to the input total', () {
      final listings = [
        _listing('1', 'active'),
        _listing('2', 'active'),
        _listing('3', 'sold'),
        _listing('4', 'withdrawn'),
      ];
      final received = [_pendingRequestFor('2')];

      final result = ListingStatusFilter.partition(listings, received);

      final totalPartitioned = result.active.length + result.coBrokeInReview.length + result.closedSold.length;
      expect(totalPartitioned, listings.length);
    });
  });
}

// app/test/features/collaboration/conversation_list_screen_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:renly/features/collaboration/conversation_list_screen.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'My Listing',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  photoUrls: [],
  status: 'active',
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
  photoUrls: [],
  status: 'open',
);

const _owner = ListingOwner(fullName: 'Owner', renNumber: '12345');

const _match = MatchCandidate(
  matchId: 'm-1',
  score: 90,
  listing: _listing,
  requirement: _requirement,
  listingOwner: _owner,
  requirementOwner: _owner,
);

CobrokeRequestCandidate _candidate(String requestId, String status) {
  return CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: requestId,
      matchId: 'm-1',
      initiatorId: 'n-2',
      status: status,
      createdAt: DateTime(2026, 9, 5),
    ),
    match: _match,
  );
}

void main() {
  test('keeps only accepted requests from received+sent, deduplicated by requestId', () {
    final received = [_candidate('req-1', 'accepted'), _candidate('req-2', 'pending')];
    final sent = [_candidate('req-3', 'accepted'), _candidate('req-1', 'accepted')];

    final result = mergeAcceptedConversations(received, sent);

    expect(result.map((c) => c.request.requestId).toSet(), {'req-1', 'req-3'});
  });

  test('returns an empty list when nothing is accepted', () {
    final received = [_candidate('req-1', 'pending')];
    final sent = [_candidate('req-2', 'declined')];

    expect(mergeAcceptedConversations(received, sent), isEmpty);
  });
}

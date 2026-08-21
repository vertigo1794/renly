// app/lib/features/matching/models/match_candidate.dart
import '../../listing/models/listing.dart';
import '../../listing/models/listing_owner.dart';
import '../../requirement/models/requirement.dart';

/// A match row joined with both full sides and both owners. Always carries
/// both sides even on screens where one side is already known from
/// context -- one shared model and one shared list-row shape across all
/// three matching screens, instead of three near-duplicate view models.
class MatchCandidate {
  final String matchId;
  final int score;
  final Listing listing;
  final Requirement requirement;
  final ListingOwner listingOwner;
  final ListingOwner requirementOwner;

  const MatchCandidate({
    required this.matchId,
    required this.score,
    required this.listing,
    required this.requirement,
    required this.listingOwner,
    required this.requirementOwner,
  });
}

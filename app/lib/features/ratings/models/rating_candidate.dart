import '../../listing/models/listing_owner.dart';
import 'rating.dart';

/// A rating row joined with the rater's display name -- reuses
/// `ListingOwner` directly rather than inventing a second name-shaped
/// model, same reuse precedent as `CobrokeRequestCandidate` wrapping
/// `MatchCandidate`.
class RatingCandidate {
  final Rating rating;
  final ListingOwner rater;

  const RatingCandidate({required this.rating, required this.rater});
}

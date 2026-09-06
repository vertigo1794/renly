import '../collaboration/models/cobroke_request_candidate.dart';
import 'models/listing.dart';

/// Pure client-side tab filters for My Inventory.
class ListingStatusFilter {
  ListingStatusFilter._();

  static List<Listing> byStatus(List<Listing> listings, String status) {
    return listings.where((listing) => listing.status == status).toList();
  }

  /// Mutually-exclusive 3-way split for the My Inventory Premium Restyle's
  /// Active / Co-Broke in Review / Closed·Sold tabs -- every input listing
  /// appears in exactly one output list, so the three lengths always sum
  /// to listings.length. `receivedRequests` is the negotiator's own
  /// receivedRequestsProvider result (requests where they are NOT the
  /// initiator, i.e. inquiries on their own listings) -- a listing moves
  /// into coBrokeInReview only when it has at least one PENDING (not
  /// accepted, not declined) request against it.
  static ({List<Listing> active, List<Listing> coBrokeInReview, List<Listing> closedSold}) partition(
    List<Listing> listings,
    List<CobrokeRequestCandidate> receivedRequests,
  ) {
    final listingIdsWithPendingRequest = receivedRequests
        .where((c) => c.request.status == 'pending')
        .map((c) => c.match.listing.listingId)
        .toSet();

    final active = <Listing>[];
    final coBrokeInReview = <Listing>[];
    final closedSold = <Listing>[];

    for (final listing in listings) {
      if (listing.status == 'sold' || listing.status == 'withdrawn') {
        closedSold.add(listing);
      } else if (listingIdsWithPendingRequest.contains(listing.listingId)) {
        coBrokeInReview.add(listing);
      } else {
        active.add(listing);
      }
    }

    return (active: active, coBrokeInReview: coBrokeInReview, closedSold: closedSold);
  }
}

import 'models/listing.dart';

/// Pure client-side tab filter for My Inventory (active/sold/withdrawn).
class ListingStatusFilter {
  ListingStatusFilter._();

  static List<Listing> byStatus(List<Listing> listings, String status) {
    return listings.where((listing) => listing.status == status).toList();
  }
}

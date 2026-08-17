/// A row from the `listing` table.
class Listing {
  final String listingId;
  final String negotiatorId;
  final String title;
  final String description;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double price;
  final int? bedrooms;
  final int? bathrooms;
  final List<String> photoUrls;
  final String status;

  const Listing({
    required this.listingId,
    required this.negotiatorId,
    required this.title,
    required this.description,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.price,
    this.bedrooms,
    this.bathrooms,
    required this.photoUrls,
    required this.status,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      listingId: json['listing_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      price: (json['price'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
    );
  }
}

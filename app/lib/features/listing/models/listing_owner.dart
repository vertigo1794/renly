/// The listing's negotiator, scoped to what PropertyDetailScreen displays
/// (name + REN number) -- deliberately not the full `Negotiator` model from
/// the auth feature, to keep this feature's Supabase reads self-contained
/// rather than reaching into another feature's model.
class ListingOwner {
  final String fullName;
  final String renNumber;

  const ListingOwner({required this.fullName, required this.renNumber});

  factory ListingOwner.fromJson(Map<String, dynamic> json) {
    return ListingOwner(
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String? ?? '',
    );
  }
}

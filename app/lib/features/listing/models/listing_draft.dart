/// A locally-saved, in-progress Post Listing form -- never touches the
/// `listing` table (no half-validated row belongs there). Text-field
/// values are stored as raw strings (not parsed num/int) since a draft
/// may be mid-edit with an incomplete or unparseable value; parsing only
/// happens for real when the resumed form is actually submitted.
class ListingDraft {
  final String draftId;
  final DateTime savedAt;
  final String title;
  final String description;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final String? price;
  final String? bedrooms;
  final String? bathrooms;
  final String? commissionSplitPercent;
  final bool titleVerified;
  final bool exclusiveMandate;

  const ListingDraft({
    required this.draftId,
    required this.savedAt,
    required this.title,
    required this.description,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    this.price,
    this.bedrooms,
    this.bathrooms,
    this.commissionSplitPercent,
    required this.titleVerified,
    required this.exclusiveMandate,
  });

  Map<String, dynamic> toJson() {
    return {
      'draft_id': draftId,
      'saved_at': savedAt.toIso8601String(),
      'title': title,
      'description': description,
      'property_type': propertyType,
      'transaction_type': transactionType,
      'state': state,
      'area': area,
      'price': price,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'commission_split_percent': commissionSplitPercent,
      'title_verified': titleVerified,
      'exclusive_mandate': exclusiveMandate,
    };
  }

  factory ListingDraft.fromJson(Map<String, dynamic> json) {
    return ListingDraft(
      draftId: json['draft_id'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      price: json['price'] as String?,
      bedrooms: json['bedrooms'] as String?,
      bathrooms: json['bathrooms'] as String?,
      commissionSplitPercent: json['commission_split_percent'] as String?,
      titleVerified: json['title_verified'] as bool,
      exclusiveMandate: json['exclusive_mandate'] as bool,
    );
  }
}

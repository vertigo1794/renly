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
  final String? sqft;
  final String? commissionSplitPercent;
  final bool titleVerified;
  final bool exclusiveMandate;

  /// The 8 fields added by the Property Detail Ultra-Premium Restyle.
  /// Numeric-ish and dropdown fields follow this class's existing
  /// convention: stored as the raw `String?` the form's controller/dropdown
  /// holds, not a parsed double?/int?, since a draft may be mid-edit with
  /// an incomplete or unparseable value. `keysOnHand`/`protectedCoBrokeReg`
  /// are plain toggles, so they follow `titleVerified`/`exclusiveMandate`'s
  /// non-nullable `bool` convention instead, defaulting false.
  final String? maintenanceFeeMyr;
  final String? tenure;
  final String? parkingBays;
  final String? floorLevel;
  final String? furnishingStatus;
  final bool keysOnHand;
  final bool protectedCoBrokeReg;
  final String? totalAgencyCommissionPercent;

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
    this.sqft,
    this.commissionSplitPercent,
    required this.titleVerified,
    required this.exclusiveMandate,
    this.maintenanceFeeMyr,
    this.tenure,
    this.parkingBays,
    this.floorLevel,
    this.furnishingStatus,
    this.keysOnHand = false,
    this.protectedCoBrokeReg = false,
    this.totalAgencyCommissionPercent,
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
      'sqft': sqft,
      'commission_split_percent': commissionSplitPercent,
      'title_verified': titleVerified,
      'exclusive_mandate': exclusiveMandate,
      'maintenance_fee_myr': maintenanceFeeMyr,
      'tenure': tenure,
      'parking_bays': parkingBays,
      'floor_level': floorLevel,
      'furnishing_status': furnishingStatus,
      'keys_on_hand': keysOnHand,
      'protected_co_broke_reg': protectedCoBrokeReg,
      'total_agency_commission_percent': totalAgencyCommissionPercent,
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
      sqft: json['sqft'] as String?,
      commissionSplitPercent: json['commission_split_percent'] as String?,
      titleVerified: json['title_verified'] as bool,
      exclusiveMandate: json['exclusive_mandate'] as bool,
      maintenanceFeeMyr: json['maintenance_fee_myr'] as String?,
      tenure: json['tenure'] as String?,
      parkingBays: json['parking_bays'] as String?,
      floorLevel: json['floor_level'] as String?,
      furnishingStatus: json['furnishing_status'] as String?,
      keysOnHand: json['keys_on_hand'] as bool? ?? false,
      protectedCoBrokeReg: json['protected_co_broke_reg'] as bool? ?? false,
      totalAgencyCommissionPercent: json['total_agency_commission_percent'] as String?,
    );
  }
}

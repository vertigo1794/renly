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

  /// Built-up size in square feet. Nullable -- absent on any listing whose
  /// owner didn't set it, never a fabricated/estimated fallback.
  final int? builtUpSqft;
  final List<String> photoUrls;
  final String status;
  final DateTime createdAt;

  /// Set only by the "Bump Listing" action (My Inventory Premium
  /// Restyle) -- kept SEPARATE from [createdAt] deliberately: createdAt is
  /// this listing's true age (backs "N Days on Market" and the
  /// Dashboard's Recent Listings relative timestamp) and must never
  /// change after creation. A bump changes ordering, never age.
  final DateTime? bumpedAt;

  /// The percentage of the eventual transaction commission this
  /// listing's owner is offering to whichever co-broker brings a
  /// qualifying buyer. Standalone from `Agreement.splitInitiator`/
  /// `splitCounterparty`, which only exists once a specific co-broke
  /// request is formalized into a deal -- this is the owner's own
  /// upfront, self-set advertised split. Null means the owner didn't set
  /// one; UI must never show a fabricated fallback percentage.
  final double? commissionSplitPercent;

  /// Self-attested by the listing's own owner -- NOT third-party
  /// verified. Defaults false so every existing call site (11+ test
  /// fixtures, `createListing`) compiles unchanged.
  final bool titleVerified;

  /// Self-attested by the listing's own owner -- NOT third-party
  /// verified. Same default-false reasoning as [titleVerified].
  final bool exclusiveMandate;

  /// Monthly maintenance/service charge in MYR. Nullable -- absent if the
  /// owner didn't set one, never estimated.
  final double? maintenanceFeeMyr;

  /// 'freehold' or 'leasehold'. Nullable -- absent if unset.
  final String? tenure;

  /// Number of covered parking bays. Nullable -- absent if unset.
  final int? parkingBays;

  /// Floor number the unit is on. Nullable -- absent if unset. Deliberately
  /// a plain int, not validated against the property's actual floor count
  /// (which this app has no record of).
  final int? floorLevel;

  /// 'furnished', 'partially_furnished', or 'unfurnished'. Nullable --
  /// absent if unset.
  final String? furnishingStatus;

  /// Self-attested by the listing's own owner -- NOT third-party verified.
  /// Same framing as [titleVerified]/[exclusiveMandate].
  final bool keysOnHand;

  /// Self-attested by the listing's own owner -- NOT third-party verified.
  /// Same framing as [keysOnHand].
  final bool protectedCoBrokeReg;

  /// The deal's total agency commission rate, standalone from
  /// [commissionSplitPercent] (which is the owner's own advertised split
  /// OF this total to a co-broker). Nullable -- absent if unset.
  final double? totalAgencyCommissionPercent;

  Listing({
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
    this.builtUpSqft,
    required this.photoUrls,
    required this.status,
    required this.createdAt,
    this.bumpedAt,
    this.commissionSplitPercent,
    this.titleVerified = false,
    this.exclusiveMandate = false,
    this.maintenanceFeeMyr,
    this.tenure,
    this.parkingBays,
    this.floorLevel,
    this.furnishingStatus,
    this.keysOnHand = false,
    this.protectedCoBrokeReg = false,
    this.totalAgencyCommissionPercent,
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
      builtUpSqft: json['built_up_sqft'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      bumpedAt: json['bumped_at'] == null ? null : DateTime.parse(json['bumped_at'] as String),
      commissionSplitPercent: (json['commission_split_percent'] as num?)?.toDouble(),
      titleVerified: json['title_verified'] as bool? ?? false,
      exclusiveMandate: json['exclusive_mandate'] as bool? ?? false,
      maintenanceFeeMyr: (json['maintenance_fee_myr'] as num?)?.toDouble(),
      tenure: json['tenure'] as String?,
      parkingBays: json['parking_bays'] as int?,
      floorLevel: json['floor_level'] as int?,
      furnishingStatus: json['furnishing_status'] as String?,
      keysOnHand: json['keys_on_hand'] as bool? ?? false,
      protectedCoBrokeReg: json['protected_co_broke_reg'] as bool? ?? false,
      totalAgencyCommissionPercent: (json['total_agency_commission_percent'] as num?)?.toDouble(),
    );
  }
}

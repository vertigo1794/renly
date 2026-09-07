/// A row from the `requirement` table.
class Requirement {
  final String requirementId;
  final String negotiatorId;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double budgetMin;
  final double budgetMax;
  final int? bedrooms;
  final List<String> photoUrls;
  final String status;

  /// Minimum bathroom count the buyer requires. Nullable -- unset means
  /// no minimum, so `MatchingEngine.score` never disqualifies on this
  /// dimension for this requirement.
  final int? bathroomsMin;

  /// Minimum built-up size (sqft) the buyer requires. Same null-means-
  /// unset semantics as [bathroomsMin].
  final int? builtUpSqftMin;

  /// The buyer's own advertised/desired co-broke split percentage --
  /// self-set by the requirement's own owner, standalone from
  /// `Listing.commissionSplitPercent` (the LISTING owner's own advertised
  /// split) and from `Agreement.splitInitiator`/`splitCounterparty`
  /// (which only exists once a deal is formalized). Null means the buyer
  /// didn't set one; UI must never show a fabricated fallback percentage.
  final double? desiredCommissionSplitPercent;

  /// Self-attested by the requirement's own owner -- NOT third-party
  /// verified. Defaults false so every existing call site compiles
  /// unchanged.
  final bool loanReady;

  /// Self-attested by the requirement's own owner -- NOT third-party
  /// verified. Same default-false reasoning as [loanReady].
  final bool urgentViewingRequired;

  /// Buyer's required tenure -- 'freehold' or 'leasehold'. Nullable --
  /// unset means no preference, so `MatchingEngine.score` never
  /// disqualifies on this dimension. When set, `MatchingEngine.score`
  /// requires an EXACT match against the listing's own `tenure` (unlike
  /// [bathroomsMin]/[builtUpSqftMin], which are minimum thresholds, this
  /// is a categorical preference).
  final String? tenurePreference;

  /// Minimum parking bays the buyer requires. Same null-means-unset,
  /// minimum-threshold semantics as [bathroomsMin].
  final int? parkingBaysMin;

  /// Minimum floor level the buyer requires. Same null-means-unset,
  /// minimum-threshold semantics as [bathroomsMin].
  final int? floorLevelMin;

  /// Buyer's required furnishing status -- 'furnished',
  /// 'partially_furnished', or 'unfurnished'. Same null-means-unset,
  /// exact-match semantics as [tenurePreference].
  final String? furnishingPreference;

  const Requirement({
    required this.requirementId,
    required this.negotiatorId,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.budgetMin,
    required this.budgetMax,
    this.bedrooms,
    required this.photoUrls,
    required this.status,
    this.bathroomsMin,
    this.builtUpSqftMin,
    this.desiredCommissionSplitPercent,
    this.loanReady = false,
    this.urgentViewingRequired = false,
    this.tenurePreference,
    this.parkingBaysMin,
    this.floorLevelMin,
    this.furnishingPreference,
  });

  factory Requirement.fromJson(Map<String, dynamic> json) {
    return Requirement(
      requirementId: json['requirement_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      budgetMin: (json['budget_min'] as num).toDouble(),
      budgetMax: (json['budget_max'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
      bathroomsMin: json['bathrooms_min'] as int?,
      builtUpSqftMin: json['built_up_sqft_min'] as int?,
      desiredCommissionSplitPercent: (json['desired_commission_split_percent'] as num?)?.toDouble(),
      loanReady: json['loan_ready'] as bool? ?? false,
      urgentViewingRequired: json['urgent_viewing_required'] as bool? ?? false,
      tenurePreference: json['tenure_preference'] as String?,
      parkingBaysMin: json['parking_bays_min'] as int?,
      floorLevelMin: json['floor_level_min'] as int?,
      furnishingPreference: json['furnishing_preference'] as String?,
    );
  }
}

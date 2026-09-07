import '../listing/models/listing.dart';
import '../requirement/models/requirement.dart';

/// Pure weighted-scoring algorithm from the project proposal §6.4. No
/// Flutter/Supabase dependency -- fully unit-testable, mirrors the
/// ListingFormatting/RequirementFormatting precedent.
class MatchingEngine {
  MatchingEngine._();

  static const qualifyingThreshold = 40;

  /// Returns null if a mandatory filter disqualifies the pair (transaction
  /// type mismatch, state mismatch, the listing not meeting the
  /// requirement's bathroomsMin/builtUpSqftMin/parkingBaysMin/
  /// floorLevelMin, when set, or the listing's tenure/furnishingStatus
  /// not exactly matching the requirement's tenurePreference/
  /// furnishingPreference, when set). Otherwise returns the weighted
  /// score (0-100), rounded to the nearest integer -- callers decide
  /// whether it clears [qualifyingThreshold].
  static int? score(Listing listing, Requirement requirement) {
    if (listing.transactionType != requirement.transactionType) return null;
    if (listing.state != requirement.state) return null;
    if (requirement.bathroomsMin != null &&
        (listing.bathrooms == null || listing.bathrooms! < requirement.bathroomsMin!)) {
      return null;
    }
    if (requirement.builtUpSqftMin != null &&
        (listing.builtUpSqft == null || listing.builtUpSqft! < requirement.builtUpSqftMin!)) {
      return null;
    }
    if (requirement.parkingBaysMin != null &&
        (listing.parkingBays == null || listing.parkingBays! < requirement.parkingBaysMin!)) {
      return null;
    }
    if (requirement.floorLevelMin != null &&
        (listing.floorLevel == null || listing.floorLevel! < requirement.floorLevelMin!)) {
      return null;
    }
    if (requirement.tenurePreference != null && listing.tenure != requirement.tenurePreference) {
      return null;
    }
    if (requirement.furnishingPreference != null && listing.furnishingStatus != requirement.furnishingPreference) {
      return null;
    }

    final location = listing.area.toLowerCase() == requirement.area.toLowerCase() ? 30 : 0;
    final price = _priceScore(listing.price, requirement.budgetMin, requirement.budgetMax);
    final propertyType = listing.propertyType == requirement.propertyType ? 25 : 0;
    final bedrooms = _bedroomScore(listing.bedrooms, requirement.bedrooms);

    return (location + price + propertyType + bedrooms).round();
  }

  /// Full weight within [budgetMin, budgetMax] and below budgetMin (still
  /// affordable). Linearly reduced from 35 to 0 between budgetMax and
  /// budgetMax * 1.10. Zero beyond that.
  static double _priceScore(double price, double budgetMin, double budgetMax) {
    if (price <= budgetMax) return 35;
    final overMax = budgetMax * 1.10;
    if (price >= overMax) return 0;
    final fraction = (overMax - price) / (overMax - budgetMax);
    return 35 * fraction;
  }

  /// Binary, not graduated -- the proposal gives no curve for this
  /// attribute. Unset requirement bedrooms (client didn't specify) scores
  /// full weight regardless of the listing's value.
  static int _bedroomScore(int? listingBedrooms, int? requirementBedrooms) {
    if (requirementBedrooms == null) return 10;
    if (listingBedrooms == requirementBedrooms) return 10;
    return 0;
  }
}

import '../listing/models/listing.dart';
import '../requirement/models/requirement.dart';
import 'matching_engine.dart';

/// Real, client-side, pre-submission match preview. Reuses the exact same
/// MatchingEngine.score() already used for real post-submission matching
/// (MatchingRepository), but performs NO database writes and sends NO
/// notifications -- purely in-memory, given an already-fetched candidate
/// list, so it's directly unit-testable with zero Supabase dependency.
/// The caller (a form body) is responsible for fetching the candidate
/// list and re-invoking this on a debounced timer as the draft changes.
class LiveMatchPreview {
  LiveMatchPreview._();

  /// Scores [candidates] (real, already-active listings) against a
  /// not-yet-submitted [draftRequirement] built from the current form
  /// values. [draftRequirement]'s requirementId/negotiatorId/status are
  /// never read by MatchingEngine.score, so placeholder values are fine.
  static LiveMatchPreviewResult forRequirement(Requirement draftRequirement, List<Listing> candidates) {
    Listing? topListing;
    int? topScore;
    var matchCount = 0;
    for (final listing in candidates) {
      final score = MatchingEngine.score(listing, draftRequirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      matchCount++;
      if (topScore == null || score > topScore) {
        topScore = score;
        topListing = listing;
      }
    }
    return LiveMatchPreviewResult(
      matchCount: matchCount,
      topMatchLabel: topListing?.title,
      topMatchScore: topScore,
    );
  }

  /// Scores [candidates] (real, open requirements) against a not-yet-
  /// submitted [draftListing]. Requirement has no natural "title" field
  /// (unlike Listing), so the top match's label is synthesized from its
  /// real propertyType + area -- e.g. "apartment buyer in Petaling Jaya"
  /// -- rather than fabricating a name.
  static LiveMatchPreviewResult forListing(Listing draftListing, List<Requirement> candidates) {
    Requirement? topRequirement;
    int? topScore;
    var matchCount = 0;
    for (final requirement in candidates) {
      final score = MatchingEngine.score(draftListing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      matchCount++;
      if (topScore == null || score > topScore) {
        topScore = score;
        topRequirement = requirement;
      }
    }
    return LiveMatchPreviewResult(
      matchCount: matchCount,
      topMatchLabel: topRequirement == null ? null : '${topRequirement.propertyType} buyer in ${topRequirement.area}',
      topMatchScore: topScore,
    );
  }

  /// The real per-viewer match score for the Property Detail screen's
  /// hero "N% MATCH" badge -- the highest MatchingEngine.score() between
  /// [listing] and any of [viewerRequirements] (the CURRENT VIEWER's own
  /// open requirements, not the listing owner's), or null if none clear
  /// qualifyingThreshold (including the trivial empty-list case). Zero DB
  /// writes, same reasoning as forRequirement/forListing -- this is a
  /// pure read-time computation, not a stored Match row.
  static int? bestScoreForListing(Listing listing, List<Requirement> viewerRequirements) {
    int? best;
    for (final requirement in viewerRequirements) {
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      if (best == null || score > best) best = score;
    }
    return best;
  }
}

class LiveMatchPreviewResult {
  const LiveMatchPreviewResult({required this.matchCount, this.topMatchLabel, this.topMatchScore});

  final int matchCount;
  final String? topMatchLabel;
  final int? topMatchScore;
}

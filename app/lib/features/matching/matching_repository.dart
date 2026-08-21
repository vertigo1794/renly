// app/lib/features/matching/matching_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing.dart';
import '../listing/models/listing_owner.dart';
import '../requirement/models/requirement.dart';
import '../requirement/requirement_repository.dart';
import 'matching_engine.dart';
import 'models/match.dart';
import 'models/match_candidate.dart';

/// The only file in this app that talks to Supabase for the matching
/// feature. Composes ListingRepository/RequirementRepository rather than
/// duplicating their queries (fetching opposing open records, fetching
/// owner info) -- matching is inherently cross-feature.
class MatchingRepository {
  MatchingRepository(this._client, this._listingRepository, this._requirementRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final RequirementRepository _requirementRepository;

  Future<void> computeAndStoreMatchesForListing(Listing listing) async {
    final requirements = await _requirementRepository.fetchBoardRequirements();
    final rows = <Map<String, dynamic>>[];
    for (final requirement in requirements) {
      if (requirement.negotiatorId == listing.negotiatorId) continue;
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': requirement.requirementId,
        'score': score,
      });
    }
    await _store(rows);
  }

  Future<void> computeAndStoreMatchesForRequirement(Requirement requirement) async {
    final listings = await _listingRepository.fetchMarketplaceListings();
    final rows = <Map<String, dynamic>>[];
    for (final listing in listings) {
      if (listing.negotiatorId == requirement.negotiatorId) continue;
      final score = MatchingEngine.score(listing, requirement);
      if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': requirement.requirementId,
        'score': score,
      });
    }
    await _store(rows);
  }

  Future<void> _store(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('match').upsert(
          rows,
          onConflict: 'listing_id,requirement_id',
          ignoreDuplicates: true,
        );
  }

  Future<List<MatchCandidate>> fetchMatchesForListing(String listingId) async {
    final rows = await _client
        .from('match')
        .select('*, listing!inner(*), requirement!inner(*)')
        .eq('listing_id', listingId)
        .order('score', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<MatchCandidate>> fetchMatchesForRequirement(String requirementId) async {
    final rows = await _client
        .from('match')
        .select('*, listing!inner(*), requirement!inner(*)')
        .eq('requirement_id', requirementId)
        .order('score', ascending: false);
    return _toCandidates(rows as List);
  }

  /// RLS on `match` already restricts rows to ones touching the caller's
  /// own listing or requirement -- no negotiatorId filter needed here.
  Future<List<MatchCandidate>> fetchMyMatches() async {
    final rows = await _client
        .from('match')
        .select('*, listing!inner(*), requirement!inner(*)')
        .order('score', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<MatchCandidate>> _toCandidates(List rows) async {
    // Collect every distinct negotiator id up front and resolve them all
    // concurrently with Future.wait, instead of awaiting ownerFor(...) once
    // per row inside the loop -- that would serialize N distinct-negotiator
    // lookups into N sequential round-trips even though fetchListingOwner
    // is per-negotiator cacheable. All three call sites use `!inner` joins
    // which should guarantee non-null embeds, but the null-guard below is
    // defensive: skip a row rather than crash if that invariant is ever
    // violated.
    final negotiatorIds = <String>{};
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final listingJson = map['listing'] as Map<String, dynamic>?;
      final requirementJson = map['requirement'] as Map<String, dynamic>?;
      if (listingJson == null || requirementJson == null) continue;
      negotiatorIds.add(listingJson['negotiator_id'] as String);
      negotiatorIds.add(requirementJson['negotiator_id'] as String);
    }

    final ownersById = Map<String, ListingOwner>.fromIterables(
      negotiatorIds,
      await Future.wait(negotiatorIds.map(_listingRepository.fetchListingOwner)),
    );

    final candidates = <MatchCandidate>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final listingJson = map['listing'] as Map<String, dynamic>?;
      final requirementJson = map['requirement'] as Map<String, dynamic>?;
      if (listingJson == null || requirementJson == null) continue;

      final match = Match.fromJson(map);
      final listing = Listing.fromJson(listingJson);
      final requirement = Requirement.fromJson(requirementJson);
      candidates.add(MatchCandidate(
        matchId: match.matchId,
        score: match.score,
        listing: listing,
        requirement: requirement,
        listingOwner: ownersById[listing.negotiatorId]!,
        requirementOwner: ownersById[requirement.negotiatorId]!,
      ));
    }
    return candidates;
  }
}

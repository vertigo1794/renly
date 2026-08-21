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
    // Cached as Futures (not resolved values) so concurrent lookups for the
    // same negotiator id across multiple match rows share one in-flight
    // request instead of firing the RPC once per row.
    final ownerFutures = <String, Future<ListingOwner>>{};
    Future<ListingOwner> ownerFor(String negotiatorId) {
      return ownerFutures.putIfAbsent(negotiatorId, () => _listingRepository.fetchListingOwner(negotiatorId));
    }

    final candidates = <MatchCandidate>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final match = Match.fromJson(map);
      final listing = Listing.fromJson(map['listing'] as Map<String, dynamic>);
      final requirement = Requirement.fromJson(map['requirement'] as Map<String, dynamic>);
      final listingOwner = await ownerFor(listing.negotiatorId);
      final requirementOwner = await ownerFor(requirement.negotiatorId);
      candidates.add(MatchCandidate(
        matchId: match.matchId,
        score: match.score,
        listing: listing,
        requirement: requirement,
        listingOwner: listingOwner,
        requirementOwner: requirementOwner,
      ));
    }
    return candidates;
  }
}

// app/lib/features/matching/matching_repository.dart
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing.dart';
import '../listing/models/listing_owner.dart';
import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
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
  MatchingRepository(
    this._client,
    this._listingRepository,
    this._requirementRepository,
    this._pushNotificationRepository,
  );

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final RequirementRepository _requirementRepository;
  final PushNotificationRepository _pushNotificationRepository;

  Future<void> computeAndStoreMatchesForListing(Listing listing) async {
    final requirements = await _requirementRepository.fetchBoardRequirements();
    // Scoring runs on a background isolate via compute() -- same
    // "don't block the UI thread with a CPU-bound loop" reasoning HTML5's
    // Web Worker exists for, and a real win once the requirement board
    // has enough rows for this loop to actually cost something.
    final scored = await compute(_scoreRequirementsAgainstListing, _ScoreForListingArgs(listing, requirements));
    final rows = <Map<String, dynamic>>[];
    final ownerByRequirementId = <String, String>{};
    for (final match in scored) {
      rows.add({
        'listing_id': listing.listingId,
        'requirement_id': match.requirementId,
        'score': match.score,
      });
      ownerByRequirementId[match.requirementId] = match.negotiatorId;
    }
    final insertedRows = await _store(rows);
    for (final row in insertedRows) {
      final requirementId = row['requirement_id'] as String?;
      final recipientId = requirementId == null ? null : ownerByRequirementId[requirementId];
      if (recipientId == null) continue;
      unawaited(_notifyMatch(recipientId, ownerSide: 'requirement', listingId: null, requirementId: requirementId));
    }
  }

  Future<void> computeAndStoreMatchesForRequirement(Requirement requirement) async {
    final listings = await _listingRepository.fetchMarketplaceListings();
    // Same background-isolate reasoning as computeAndStoreMatchesForListing.
    final scored = await compute(_scoreListingsAgainstRequirement, _ScoreForRequirementArgs(requirement, listings));
    final rows = <Map<String, dynamic>>[];
    final ownerByListingId = <String, String>{};
    for (final match in scored) {
      rows.add({
        'listing_id': match.listingId,
        'requirement_id': requirement.requirementId,
        'score': match.score,
      });
      ownerByListingId[match.listingId] = match.negotiatorId;
    }
    final insertedRows = await _store(rows);
    for (final row in insertedRows) {
      final listingId = row['listing_id'] as String?;
      final recipientId = listingId == null ? null : ownerByListingId[listingId];
      if (recipientId == null) continue;
      unawaited(_notifyMatch(recipientId, ownerSide: 'listing', listingId: listingId, requirementId: null));
    }
  }

  /// ownerSide/listingId/requirementId describe which screen the
  /// RECIPIENT should land on (their own side of the match), not the side
  /// that was just posted -- see deep_link.dart's deepLinkRouteFor.
  Future<void> _notifyMatch(
    String recipientId, {
    required String ownerSide,
    required String? listingId,
    required String? requirementId,
  }) async {
    try {
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: recipientId,
        category: 'match',
        title: 'push_match_title'.tr(),
        body: 'push_match_body'.tr(),
        deepLinkData: {
          'owner_side': ownerSide,
          'listing_id': ?listingId,
          'requirement_id': ?requirementId,
        },
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the match that was already stored.
    }
  }

  Future<List<Map<String, dynamic>>> _store(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];
    // .select() after an ignoreDuplicates upsert only returns rows that
    // were genuinely inserted -- PostgREST's RETURNING skips rows the
    // ON CONFLICT DO NOTHING clause suppressed. Without this, every
    // re-computation would re-notify recipients for matches that already
    // existed.
    return _client.from('match').upsert(
          rows,
          onConflict: 'listing_id,requirement_id',
          ignoreDuplicates: true,
        ).select();
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

  /// Top area by match count in the last 24h, among matches on the
  /// negotiator's OWN listings only (Co-Broking Radar's own filter,
  /// mirrored here for the Market Pulse strip's "N New Matches in {area}"
  /// copy). Returns null when there are zero qualifying matches -- the
  /// caller hides the whole strip rather than showing a fabricated "0".
  Future<({String area, int count})?> fetchTopMatchAreaLast24h(String negotiatorId) async {
    final since = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
    final rows = await _client
        .from('match')
        .select('listing!inner(area, negotiator_id)')
        .eq('listing.negotiator_id', negotiatorId)
        .gte('created_at', since);
    final counts = <String, int>{};
    for (final row in rows as List) {
      final area = (row as Map<String, dynamic>)['listing']['area'] as String;
      counts[area] = (counts[area] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (area: top.key, count: top.value);
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

/// Argument bundle for [_scoreRequirementsAgainstListing] -- compute()
/// passes exactly one argument to the isolate, so the listing and the
/// full requirement list travel together. Listing/Requirement are plain
/// data classes (String/int/double/DateTime/`List<String>` fields only),
/// which Dart's isolate messaging can send without extra serialization.
class _ScoreForListingArgs {
  const _ScoreForListingArgs(this.listing, this.requirements);
  final Listing listing;
  final List<Requirement> requirements;
}

class _ScoreForRequirementArgs {
  const _ScoreForRequirementArgs(this.requirement, this.listings);
  final Requirement requirement;
  final List<Listing> listings;
}

/// One qualifying match found by the background isolate -- carries just
/// enough to build the `match` table row and resolve the push-notification
/// recipient back on the main isolate, not the full Requirement/Listing.
class _ScoredRequirementMatch {
  const _ScoredRequirementMatch(this.requirementId, this.negotiatorId, this.score);
  final String requirementId;
  final String negotiatorId;
  final int score;
}

class _ScoredListingMatch {
  const _ScoredListingMatch(this.listingId, this.negotiatorId, this.score);
  final String listingId;
  final String negotiatorId;
  final int score;
}

/// Runs on a background isolate via compute() -- must be a top-level (or
/// static) function, not a closure, and must not touch `this`/instance
/// state, which is exactly why this scoring loop was already a pure
/// function of its inputs (MatchingEngine.score) before this change.
List<_ScoredRequirementMatch> _scoreRequirementsAgainstListing(_ScoreForListingArgs args) {
  final results = <_ScoredRequirementMatch>[];
  for (final requirement in args.requirements) {
    if (requirement.negotiatorId == args.listing.negotiatorId) continue;
    final score = MatchingEngine.score(args.listing, requirement);
    if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
    results.add(_ScoredRequirementMatch(requirement.requirementId, requirement.negotiatorId, score));
  }
  return results;
}

List<_ScoredListingMatch> _scoreListingsAgainstRequirement(_ScoreForRequirementArgs args) {
  final results = <_ScoredListingMatch>[];
  for (final listing in args.listings) {
    if (listing.negotiatorId == args.requirement.negotiatorId) continue;
    final score = MatchingEngine.score(listing, args.requirement);
    if (score == null || score < MatchingEngine.qualifyingThreshold) continue;
    results.add(_ScoredListingMatch(listing.listingId, listing.negotiatorId, score));
  }
  return results;
}

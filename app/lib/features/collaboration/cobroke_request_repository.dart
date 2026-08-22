// app/lib/features/collaboration/cobroke_request_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing.dart';
import '../listing/models/listing_owner.dart';
import '../matching/models/match.dart';
import '../matching/models/match_candidate.dart';
import '../requirement/models/requirement.dart';
import 'models/cobroke_request.dart';
import 'models/cobroke_request_candidate.dart';

/// The only file in this app that talks to Supabase for the cobroke_request
/// feature. Composes ListingRepository (for owner lookups) rather than
/// duplicating that query, same reuse precedent as MatchingRepository.
class CobrokeRequestRepository {
  CobrokeRequestRepository(this._client, this._listingRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;

  Future<void> createRequest({required String matchId, required String initiatorId}) async {
    await _client.from('cobroke_request').insert({
      'match_id': matchId,
      'initiator_id': initiatorId,
    });
  }

  Future<void> acceptRequest(String requestId) {
    return _client.from('cobroke_request').update({'status': 'accepted'}).eq('request_id', requestId);
  }

  Future<void> declineRequest(String requestId) {
    return _client.from('cobroke_request').update({'status': 'declined'}).eq('request_id', requestId);
  }

  Future<List<CobrokeRequestCandidate>> fetchReceivedRequests(String negotiatorId) async {
    final rows = await _client
        .from('cobroke_request')
        .select('*, match!inner(*, listing!inner(*), requirement!inner(*))')
        .neq('initiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<CobrokeRequestCandidate>> fetchSentRequests(String negotiatorId) async {
    final rows = await _client
        .from('cobroke_request')
        .select('*, match!inner(*, listing!inner(*), requirement!inner(*))')
        .eq('initiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return _toCandidates(rows as List);
  }

  Future<List<CobrokeRequestCandidate>> _toCandidates(List rows) async {
    final ownerIds = <String>{};
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final matchJson = map['match'] as Map<String, dynamic>;
      final listingJson = matchJson['listing'] as Map<String, dynamic>;
      final requirementJson = matchJson['requirement'] as Map<String, dynamic>;
      ownerIds.add(listingJson['negotiator_id'] as String);
      ownerIds.add(requirementJson['negotiator_id'] as String);
    }

    final ownersById = Map<String, ListingOwner>.fromIterables(
      ownerIds,
      await Future.wait(ownerIds.map(_listingRepository.fetchListingOwner)),
    );

    final candidates = <CobrokeRequestCandidate>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final request = CobrokeRequest.fromJson(map);
      final matchJson = map['match'] as Map<String, dynamic>;
      final match = Match.fromJson(matchJson);
      final listing = Listing.fromJson(matchJson['listing'] as Map<String, dynamic>);
      final requirement = Requirement.fromJson(matchJson['requirement'] as Map<String, dynamic>);
      candidates.add(CobrokeRequestCandidate(
        request: request,
        match: MatchCandidate(
          matchId: match.matchId,
          score: match.score,
          listing: listing,
          requirement: requirement,
          listingOwner: ownersById[listing.negotiatorId]!,
          requirementOwner: ownersById[requirement.negotiatorId]!,
        ),
      ));
    }
    return candidates;
  }
}

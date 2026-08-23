import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import 'models/rating.dart';
import 'models/rating_candidate.dart';

/// The only file in this app that talks to Supabase for the ratings
/// feature. Composes ListingRepository for rater-name lookups, same reuse
/// precedent as CobrokeRequestRepository/MessageRepository.
class RatingRepository {
  RatingRepository(this._client, this._listingRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;

  Future<void> createRating({
    required String agreementId,
    required String raterId,
    required String ratedId,
    required int stars,
    String? reviewText,
  }) async {
    await _client.from('rating').insert({
      'agreement_id': agreementId,
      'rater_id': raterId,
      'rated_id': ratedId,
      'stars': stars,
      'review_text': reviewText,
    });
  }

  /// Chains .select() after the update and throws if the result is empty
  /// -- PostgREST returns 204 (success) on a zero-row RLS-rejected UPDATE
  /// (e.g. the 24-hour edit window has expired), the same silent-failure
  /// shape AgreementRepository's final-review fix already had to correct
  /// once in this codebase.
  Future<void> updateRating({
    required String ratingId,
    required int stars,
    String? reviewText,
  }) async {
    final rows = await _client
        .from('rating')
        .update({'stars': stars, 'review_text': reviewText})
        .eq('rating_id', ratingId)
        .select();
    if (rows.isEmpty) {
      throw StateError('Rating update was rejected (edit window expired or not permitted)');
    }
  }

  Future<Rating?> fetchMyRatingForAgreement({
    required String agreementId,
    required String raterId,
  }) async {
    final row = await _client
        .from('rating')
        .select()
        .eq('agreement_id', agreementId)
        .eq('rater_id', raterId)
        .maybeSingle();
    if (row == null) return null;
    return Rating.fromJson(row);
  }

  /// Bulk-resolves rater names via Future.wait over the distinct rater ids
  /// in the result set, not a sequential per-row await -- same concurrent
  /// resolution pattern MatchingRepository/CobrokeRequestRepository's
  /// _toCandidates methods already establish.
  Future<List<RatingCandidate>> fetchRatingsForNegotiator(String negotiatorId) async {
    final rows = await _client
        .from('rating')
        .select()
        .eq('rated_id', negotiatorId)
        .order('created_at', ascending: false);
    final ratings = (rows as List).map((row) => Rating.fromJson(row as Map<String, dynamic>)).toList();

    final raterIds = ratings.map((r) => r.raterId).toSet();
    final ownersById = Map<String, ListingOwner>.fromIterables(
      raterIds,
      await Future.wait(raterIds.map(_listingRepository.fetchListingOwner)),
    );

    return ratings
        .map((rating) => RatingCandidate(rating: rating, rater: ownersById[rating.raterId]!))
        .toList();
  }
}

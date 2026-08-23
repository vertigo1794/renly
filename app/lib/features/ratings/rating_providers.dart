import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import 'rating_repository.dart';
import 'models/rating.dart';
import 'models/rating_candidate.dart';

final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  return RatingRepository(Supabase.instance.client, ref.watch(listingRepositoryProvider));
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// The current viewer's own rating for one agreement, if any -- used to
/// decide whether MyRequestsScreen shows Rate, Edit rating, or a static
/// "you rated" label. autoDispose is REQUIRED, not the default, in this
/// project's pinned Riverpod version (2.6.1).
final myRatingForAgreementProvider = FutureProvider.autoDispose.family<Rating?, String>((ref, agreementId) {
  final raterId = ref.watch(currentNegotiatorIdProvider);
  if (raterId == null) return Future.value(null);
  return ref.watch(ratingRepositoryProvider).fetchMyRatingForAgreement(agreementId: agreementId, raterId: raterId);
});

/// All ratings received by one negotiator, with rater names resolved --
/// one provider, two consumers: ProfileScreen's average computation and
/// ReviewsScreen's full list.
final ratingsForNegotiatorProvider = FutureProvider.autoDispose.family<List<RatingCandidate>, String>((ref, negotiatorId) {
  return ref.watch(ratingRepositoryProvider).fetchRatingsForNegotiator(negotiatorId);
});

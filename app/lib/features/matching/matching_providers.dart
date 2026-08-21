// app/lib/features/matching/matching_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import '../requirement/requirement_providers.dart';
import 'matching_repository.dart';
import 'models/match_candidate.dart';

final matchingRepositoryProvider = Provider<MatchingRepository>((ref) {
  return MatchingRepository(
    Supabase.instance.client,
    ref.watch(listingRepositoryProvider),
    ref.watch(requirementRepositoryProvider),
  );
});

/// Same session-state read as listing_providers.dart/requirement_providers.dart's
/// currentNegotiatorIdProvider -- duplicated here rather than imported from
/// a sibling feature, so this feature only depends on auth for something
/// this basic.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

final matchesForListingProvider = FutureProvider.family<List<MatchCandidate>, String>((ref, listingId) {
  return ref.watch(matchingRepositoryProvider).fetchMatchesForListing(listingId);
});

final matchesForRequirementProvider = FutureProvider.family<List<MatchCandidate>, String>((ref, requirementId) {
  return ref.watch(matchingRepositoryProvider).fetchMatchesForRequirement(requirementId);
});

final myMatchesProvider = FutureProvider<List<MatchCandidate>>((ref) {
  return ref.watch(matchingRepositoryProvider).fetchMyMatches();
});

// app/lib/features/collaboration/cobroke_request_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import 'cobroke_request_repository.dart';
import 'models/cobroke_request_candidate.dart';

final cobrokeRequestRepositoryProvider = Provider<CobrokeRequestRepository>((ref) {
  return CobrokeRequestRepository(Supabase.instance.client, ref.watch(listingRepositoryProvider));
});

/// Same session-state read as the copies in listing_providers.dart,
/// requirement_providers.dart, and matching_providers.dart -- duplicated
/// here rather than imported from a sibling feature, same established
/// reasoning (see this plan's Global Constraints).
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// Requests where the current negotiator is NOT the initiator -- these are
/// the ones they can act on (accept/decline).
final receivedRequestsProvider = FutureProvider<List<CobrokeRequestCandidate>>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) return Future.value(const []);
  return ref.watch(cobrokeRequestRepositoryProvider).fetchReceivedRequests(negotiatorId);
});

/// Requests the current negotiator initiated -- read-only status view.
final sentRequestsProvider = FutureProvider<List<CobrokeRequestCandidate>>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) return Future.value(const []);
  return ref.watch(cobrokeRequestRepositoryProvider).fetchSentRequests(negotiatorId);
});

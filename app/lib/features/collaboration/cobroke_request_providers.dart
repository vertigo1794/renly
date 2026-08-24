// app/lib/features/collaboration/cobroke_request_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import '../notifications/notification_providers.dart';
import 'cobroke_request_repository.dart';
import 'models/cobroke_request_candidate.dart';

final cobrokeRequestRepositoryProvider = Provider<CobrokeRequestRepository>((ref) {
  return CobrokeRequestRepository(
    Supabase.instance.client,
    ref.watch(listingRepositoryProvider),
    ref.watch(pushNotificationRepositoryProvider),
  );
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
///
/// autoDispose (unlike the sibling myMatchesProvider/matchesForListingProvider):
/// a request's status can change from the OTHER party's action, and there's
/// no client-side invalidation path available to the viewing party for that
/// -- so refetch-on-screen-entry is the correct default here, unlike match
/// data, which only ever changes from actions the SAME viewer takes.
final receivedRequestsProvider = FutureProvider.autoDispose<List<CobrokeRequestCandidate>>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) return Future.value(const []);
  return ref.watch(cobrokeRequestRepositoryProvider).fetchReceivedRequests(negotiatorId);
});

/// Requests the current negotiator initiated -- read-only status view.
///
/// autoDispose for the same reason as receivedRequestsProvider above: the
/// counterparty's accept/decline is the OTHER party's action, so this
/// provider has no client-side invalidation path when it happens and must
/// refetch on screen entry instead of relying on a stale cached value.
final sentRequestsProvider = FutureProvider.autoDispose<List<CobrokeRequestCandidate>>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) return Future.value(const []);
  return ref.watch(cobrokeRequestRepositoryProvider).fetchSentRequests(negotiatorId);
});

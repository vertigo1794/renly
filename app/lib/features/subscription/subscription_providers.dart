import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'models/subscription_status.dart';
import 'subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// autoDispose is REQUIRED, not the default, in this project's pinned
/// Riverpod version (2.6.1) -- without it, popping SubscriptionScreen
/// would leak the underlying Realtime channel for the rest of the app's
/// process lifetime, the same class of bug Messaging's final review
/// found and fixed once already.
final subscriptionStatusProvider = StreamProvider.autoDispose<SubscriptionStatus>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    return Stream.error(StateError('No authenticated negotiator.'));
  }
  return ref.watch(subscriptionRepositoryProvider).subscriptionStream(negotiatorId);
});

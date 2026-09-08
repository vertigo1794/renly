import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'profile_repository.dart';
import 'models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// The current negotiator's own profile. autoDispose (not .family -- there
/// is only ever one "my profile" per session, no key needed): a fresh
/// fetch on every ProfileScreen visit is correct here, not a lingering
/// cached value from a prior session.
final myProfileProvider = FutureProvider.autoDispose<Profile>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    throw StateError('myProfileProvider watched with no active session');
  }
  return ref.watch(profileRepositoryProvider).fetchMyProfile(negotiatorId);
});

/// (activeListings, dealsClosed, coBrokeVolume) -- all three fetched
/// concurrently via Future.wait, not sequential awaits, same
/// concurrent-resolution pattern established across every prior
/// milestone's repository code. Future.wait<dynamic> since the three
/// results have different types (int, int, double); each is cast back to
/// its real type before returning the tuple.
final profileCountsProvider = FutureProvider.autoDispose<(int, int, double)>((ref) async {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    throw StateError('profileCountsProvider watched with no active session');
  }
  final repository = ref.watch(profileRepositoryProvider);
  final results = await Future.wait<dynamic>([
    repository.countActiveListings(negotiatorId),
    repository.countDealsClosed(),
    repository.fetchCoBrokeVolume(negotiatorId),
  ]);
  return (results[0] as int, results[1] as int, results[2] as double);
});

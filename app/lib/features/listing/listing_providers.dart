// app/lib/features/listing/listing_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'listing_repository.dart';
import 'models/listing.dart';
import 'models/listing_owner.dart';

final listingRepositoryProvider = Provider<ListingRepository>((ref) {
  return ListingRepository(Supabase.instance.client);
});

/// Reads the current session's user id -- not a Supabase query, just
/// session state already tracked by Milestone 2's authStateProvider.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

final marketplaceListingsProvider = FutureProvider<List<Listing>>((ref) {
  return ref.watch(listingRepositoryProvider).fetchMarketplaceListings();
});

final myListingsProvider = FutureProvider.family<List<Listing>, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).fetchOwnListings(negotiatorId);
});

final listingDetailProvider = FutureProvider.family<Listing, String>((ref, listingId) {
  return ref.watch(listingRepositoryProvider).fetchListingById(listingId);
});

final listingOwnerProvider = FutureProvider.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).fetchListingOwner(negotiatorId);
});

final activeListingCountProvider = FutureProvider.family<int, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).countActiveListings(negotiatorId);
});

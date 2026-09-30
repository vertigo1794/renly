// app/lib/features/listing/listing_providers.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/mysql_config.dart';
import '../auth/auth_providers.dart';
import 'listing_repository.dart';
import 'models/listing.dart';
import 'models/listing_owner.dart';
import 'mysql_view_counter_service.dart';

final listingRepositoryProvider = Provider<ListingRepository>((ref) {
  return ListingRepository(Supabase.instance.client);
});

/// Genuinely separate MySQL database (view-counter demo feature) -- see
/// MysqlViewCounterService's own doc comment. Config missing/invalid just
/// means the service's own methods become no-ops.
final mysqlViewCounterServiceProvider = Provider<MysqlViewCounterService>((ref) {
  // dotenv.env throws NotInitializedError if dotenv.load() was never called
  // (true in every widget test -- they don't run main()'s startup code).
  final config = dotenv.isInitialized
      ? MysqlConfig.fromEnvironment(dotenv.env)
      : null;
  return MysqlViewCounterService(config);
});

/// Reads the current session's user id -- not a Supabase query, just
/// session state already tracked by Milestone 2's authStateProvider.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

const _marketplaceCacheKey = 'marketplace_listings_cache';

/// True only when [marketplaceListingsProvider]'s current data came from
/// the offline cache (a live fetch failed) rather than a real network
/// response. MarketplaceScreen watches this to show a "showing offline
/// data" indicator instead of silently passing off stale data as fresh.
final marketplaceIsOfflineCacheProvider = StateProvider<bool>((ref) => false);

/// Marketplace is the one feed cached for offline use (most demonstrable,
/// most likely to be checked while genuinely out of signal) -- not a
/// blanket offline-sync engine for the whole app. On a successful fetch,
/// the real result is snapshotted to SharedPreferences (same
/// upsert-a-JSON-blob pattern as listing_drafts_provider.dart); on
/// failure, that snapshot is served instead of a bare error screen.
final marketplaceListingsProvider = FutureProvider<List<Listing>>((ref) async {
  final repository = ref.watch(listingRepositoryProvider);
  try {
    final listings = await repository.fetchMarketplaceListings();
    unawaited(_cacheMarketplaceListings(listings));
    ref.read(marketplaceIsOfflineCacheProvider.notifier).state = false;
    return listings;
  } catch (e) {
    final cached = await _loadCachedMarketplaceListings();
    if (cached == null) rethrow;
    ref.read(marketplaceIsOfflineCacheProvider.notifier).state = true;
    return cached;
  }
});

Future<void> _cacheMarketplaceListings(List<Listing> listings) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_marketplaceCacheKey, jsonEncode(listings.map((l) => l.toJson()).toList()));
}

Future<List<Listing>?> _loadCachedMarketplaceListings() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_marketplaceCacheKey);
  if (raw == null) return null;
  final decoded = jsonDecode(raw) as List;
  return decoded.map((e) => Listing.fromJson(e as Map<String, dynamic>)).toList();
}

final myListingsProvider = FutureProvider.family<List<Listing>, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).fetchOwnListings(negotiatorId);
});

final listingDetailProvider = FutureProvider.family<Listing, String>((ref, listingId) {
  return ref.watch(listingRepositoryProvider).fetchListingById(listingId);
});

final listingOwnerProvider = FutureProvider.autoDispose.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).fetchListingOwner(negotiatorId);
});

final activeListingCountProvider = FutureProvider.family<int, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).countActiveListings(negotiatorId);
});

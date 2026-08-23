import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/listing.dart';
import 'models/listing_owner.dart';

/// The only file in this app that talks to Supabase for the listing
/// feature. Screens call these methods; nothing else touches
/// `SupabaseClient` for listings.
class ListingRepository {
  ListingRepository(this._client);

  final SupabaseClient _client;

  Future<List<Listing>> fetchMarketplaceListings() async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<Listing>> fetchOwnListings(String negotiatorId) async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('negotiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<Listing> fetchListingById(String listingId) async {
    final row = await _client.from('listing').select().eq('listing_id', listingId).single();
    return Listing.fromJson(row);
  }

  /// Goes through the `get_listing_owner_info` security-definer RPC
  /// (0004_listing_hardening.sql) rather than selecting from `negotiator`
  /// directly: negotiator_select_own only lets a user read their OWN row,
  /// so a plain select here returned zero rows for every listing you don't
  /// own. The RPC returns only full_name/ren_number, so this doesn't widen
  /// access to ic_number, phone_number or verification_status.
  Future<ListingOwner> fetchListingOwner(String negotiatorId) async {
    final rows = await _client.rpc(
      'get_listing_owner_info',
      params: {'p_negotiator_id': negotiatorId},
    ) as List;
    if (rows.isEmpty) {
      throw StateError('Negotiator not found: $negotiatorId');
    }
    return ListingOwner.fromJson(rows.first as Map<String, dynamic>);
  }

  /// The `listing-photos` bucket is private, so photos can only be rendered
  /// through a short-lived signed URL (1 hour).
  Future<String> createSignedUrl(String path) {
    return _client.storage.from('listing-photos').createSignedUrl(path, 3600);
  }

  Future<String> uploadListingPhoto({
    required String negotiatorId,
    required String listingId,
    required int index,
    required Uint8List bytes,
  }) async {
    final path = '$negotiatorId/$listingId/$index.jpg';
    await _client.storage.from('listing-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// Creates the listing row WITHOUT photos (photo_urls defaults to '{}').
  /// Photos are uploaded after this returns, using the new listing_id in
  /// their Storage path, then attached via updateListingPhotos.
  Future<Listing> createListing({
    required String negotiatorId,
    required String title,
    required String description,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double price,
    int? bedrooms,
    int? bathrooms,
  }) async {
    final row = await _client
        .from('listing')
        .insert({
          'negotiator_id': negotiatorId,
          'title': title,
          'description': description,
          'property_type': propertyType,
          'transaction_type': transactionType,
          'state': state,
          'area': area,
          'price': price,
          'bedrooms': bedrooms,
          'bathrooms': bathrooms,
        })
        .select()
        .single();
    return Listing.fromJson(row);
  }

  Future<void> updateListingPhotos({required String listingId, required List<String> photoUrls}) {
    return _client.from('listing').update({'photo_urls': photoUrls}).eq('listing_id', listingId);
  }

  Future<void> updateListingStatus({required String listingId, required String status}) {
    return _client.from('listing').update({'status': status}).eq('listing_id', listingId);
  }

  Future<int> countActiveListings(String negotiatorId) async {
    final response = await _client
        .from('listing')
        .select('listing_id')
        .eq('negotiator_id', negotiatorId)
        .eq('status', 'active')
        .count(CountOption.exact);
    return response.count;
  }
}

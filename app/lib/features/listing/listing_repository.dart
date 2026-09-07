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

  /// Ordered by bumped_at first (nulls last, so a never-bumped listing
  /// doesn't outrank a genuinely just-bumped one), then created_at --
  /// composing two .order() calls into one multi-key ORDER BY. A listing
  /// that was never bumped sorts purely by its real creation time; a
  /// bumped listing jumps to the top by its bump time. createdAt itself
  /// is never touched by a bump, so "N Days on Market" stays accurate.
  Future<List<Listing>> fetchMarketplaceListings() async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('status', 'active')
        .order('bumped_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<Listing>> fetchOwnListings(String negotiatorId) async {
    final rows = await _client
        .from('listing')
        .select()
        .eq('negotiator_id', negotiatorId)
        .order('bumped_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Listing.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<Listing> fetchListingById(String listingId) async {
    final row = await _client.from('listing').select().eq('listing_id', listingId).single();
    return Listing.fromJson(row);
  }

  /// Goes through the `get_negotiator_public_info` security-definer RPC
  /// (0004_listing_hardening.sql, renamed in 0015) rather than selecting
  /// from `negotiator` directly: negotiator_select_own only lets a user
  /// read their OWN row, so a plain select here returned zero rows for
  /// every listing you don't own. The RPC returns only
  /// full_name/ren_number, so this doesn't widen access to ic_number,
  /// phone_number or verification_status.
  Future<ListingOwner> fetchListingOwner(String negotiatorId) async {
    final rows = await _client.rpc(
      'get_negotiator_public_info',
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
    int? builtUpSqft,
    double? commissionSplitPercent,
    bool titleVerified = false,
    bool exclusiveMandate = false,
    double? maintenanceFeeMyr,
    String? tenure,
    int? parkingBays,
    int? floorLevel,
    String? furnishingStatus,
    bool keysOnHand = false,
    bool protectedCoBrokeReg = false,
    double? totalAgencyCommissionPercent,
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
          'built_up_sqft': builtUpSqft,
          'commission_split_percent': commissionSplitPercent,
          'title_verified': titleVerified,
          'exclusive_mandate': exclusiveMandate,
          'maintenance_fee_myr': maintenanceFeeMyr,
          'tenure': tenure,
          'parking_bays': parkingBays,
          'floor_level': floorLevel,
          'furnishing_status': furnishingStatus,
          'keys_on_hand': keysOnHand,
          'protected_co_broke_reg': protectedCoBrokeReg,
          'total_agency_commission_percent': totalAgencyCommissionPercent,
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

  /// Permanently removes the listing row. Every downstream table (match,
  /// cobroke_request, message, agreement, rating) cascades on delete at
  /// the database level -- the UI is responsible for blocking this when
  /// the listing has an accepted co-broke request, since that represents
  /// real deal/chat history worth preserving that this call would
  /// otherwise silently destroy.
  Future<void> deleteListing(String listingId) {
    return _client.from('listing').delete().eq('listing_id', listingId);
  }

  /// Real "resurface to top of feed" action -- sets bumped_at to now,
  /// which fetchMarketplaceListings/fetchOwnListings's own ordering
  /// already accounts for. Never touches created_at.
  Future<void> bumpListing(String listingId) {
    return _client.from('listing').update({'bumped_at': DateTime.now().toIso8601String()}).eq('listing_id', listingId);
  }

  /// General field update for the Edit Listing flow. Deliberately does
  /// NOT touch negotiator_id, status, photo_urls, created_at, or
  /// bumped_at -- each of those has its own dedicated update path
  /// (updateListingPhotos, updateListingStatus, bumpListing) or must
  /// never change after creation.
  Future<void> updateListingDetails({
    required String listingId,
    required String title,
    required String description,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double price,
    int? bedrooms,
    int? bathrooms,
    int? builtUpSqft,
    double? commissionSplitPercent,
    required bool titleVerified,
    required bool exclusiveMandate,
    double? maintenanceFeeMyr,
    String? tenure,
    int? parkingBays,
    int? floorLevel,
    String? furnishingStatus,
    bool keysOnHand = false,
    bool protectedCoBrokeReg = false,
    double? totalAgencyCommissionPercent,
  }) {
    return _client.from('listing').update({
      'title': title,
      'description': description,
      'property_type': propertyType,
      'transaction_type': transactionType,
      'state': state,
      'area': area,
      'price': price,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'built_up_sqft': builtUpSqft,
      'commission_split_percent': commissionSplitPercent,
      'title_verified': titleVerified,
      'exclusive_mandate': exclusiveMandate,
      'maintenance_fee_myr': maintenanceFeeMyr,
      'tenure': tenure,
      'parking_bays': parkingBays,
      'floor_level': floorLevel,
      'furnishing_status': furnishingStatus,
      'keys_on_hand': keysOnHand,
      'protected_co_broke_reg': protectedCoBrokeReg,
      'total_agency_commission_percent': totalAgencyCommissionPercent,
    }).eq('listing_id', listingId);
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

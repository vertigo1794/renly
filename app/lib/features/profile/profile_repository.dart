// app/lib/features/profile/profile_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/profile.dart';

/// The only file in this app that talks to Supabase for the profile
/// feature. Composes a follow-up `agency` lookup rather than a join or
/// RPC -- `agency_select_all` already lets any authenticated user read
/// agency rows, so a plain second query is simplest.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile> fetchMyProfile(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('negotiator_id, full_name, ren_number, agency_id, territory, property_specialisation, verification_status, avatar_url')
        .eq('negotiator_id', negotiatorId)
        .single();
    final agencyId = row['agency_id'] as String?;
    String? agencyName;
    if (agencyId != null) {
      final agencyRow = await _client
          .from('agency')
          .select('firm_name')
          .eq('agency_id', agencyId)
          .maybeSingle();
      agencyName = agencyRow?['firm_name'] as String?;
    }
    return Profile.fromJson(row, agencyName: agencyName);
  }

  Future<void> updateProfile({
    required String negotiatorId,
    required String? territory,
    required String? propertySpecialisation,
  }) {
    return _client.from('negotiator').update({
      'territory': territory,
      'property_specialisation': propertySpecialisation,
    }).eq('negotiator_id', negotiatorId);
  }

  /// The `avatar-photos` bucket is public (unlike `listing-photos`/
  /// `requirement-photos`, both private + signed-URL), so this returns the
  /// full public URL directly -- no signing step needed at any of this
  /// URL's 9+ display call sites. Does NOT write `avatar_url` on the
  /// negotiator row -- callers persist the returned URL via
  /// [updateAvatarUrl], same two-step split as
  /// `ListingRepository.uploadListingPhoto`/`updateListingPhotos`.
  Future<String> uploadAvatar({required String negotiatorId, required Uint8List bytes}) async {
    final path = '$negotiatorId/avatar.jpg';
    await _client.storage.from('avatar-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final publicUrl = _client.storage.from('avatar-photos').getPublicUrl(path);
    // Cache-bust: the storage path is fixed ({negotiatorId}/avatar.jpg), so
    // getPublicUrl returns the IDENTICAL string on every re-upload. Flutter's
    // NetworkImage cache (and NegotiatorAvatar's own avatarUrl-changed
    // detection) is keyed by URL, so without this every already-rendered
    // avatar for this negotiator would keep showing the old photo bytes
    // until app restart. Supabase's public URL serving ignores unknown
    // query params, so this still resolves to the same underlying object.
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> updateAvatarUrl({required String negotiatorId, required String avatarUrl}) {
    return _client.from('negotiator').update({'avatar_url': avatarUrl}).eq('negotiator_id', negotiatorId);
  }

  /// Best-effort heartbeat -- see `_PresenceHeartbeat` in main.dart for the
  /// caller. A failure here (offline, backend hiccup) must never surface an
  /// error or block the app; callers swallow exceptions from this method.
  Future<void> updateLastSeen({required String negotiatorId}) {
    return _client.from('negotiator').update({'last_seen_at': DateTime.now().toIso8601String()}).eq('negotiator_id', negotiatorId);
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

  /// No negotiator_id filter needed -- agreement_select's RLS already
  /// scopes every visible row to one where the current user is a party
  /// (initiator, or owner of the underlying match's listing/requirement),
  /// so a plain count under that policy is already "my deals."
  Future<int> countDealsClosed() async {
    final response = await _client
        .from('agreement')
        .select('agreement_id')
        .eq('status', 'accepted')
        .count(CountOption.exact);
    return response.count;
  }

  /// Sums `listing.price` across every accepted agreement this negotiator
  /// is a party to. No `negotiator_id` filter in the query itself --
  /// `agreement_select`'s own RLS policy (0009_agreement.sql) already
  /// scopes visible rows to ones where the current user is a party (the
  /// agreement's own initiator, or the owner of the underlying match's
  /// listing/requirement), same reasoning as countDealsClosed() above. The
  /// `negotiatorId` param exists only for interface symmetry with this
  /// file's other counting methods.
  ///
  /// Returns 0.0 (never null, never a fabricated non-zero fallback) when
  /// there are no accepted agreements yet -- a real "no volume yet" fact.
  Future<double> fetchCoBrokeVolume(String negotiatorId) async {
    final rows = await _client
        .from('agreement')
        .select('cobroke_request!inner(match!inner(listing!inner(price)))')
        .eq('status', 'accepted') as List;
    var total = 0.0;
    for (final row in rows) {
      final cobrokeRequest = row['cobroke_request'] as Map<String, dynamic>?;
      final match = cobrokeRequest?['match'] as Map<String, dynamic>?;
      final listing = match?['listing'] as Map<String, dynamic>?;
      final price = listing?['price'] as num?;
      if (price != null) total += price.toDouble();
    }
    return total;
  }
}

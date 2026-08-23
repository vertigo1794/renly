// app/lib/features/profile/profile_repository.dart
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
        .select('negotiator_id, full_name, ren_number, agency_id, territory, property_specialisation, verification_status')
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
}

// app/lib/features/requirement/requirement_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/models/listing_owner.dart';
import 'models/requirement.dart';

/// The only file in this app that talks to Supabase for the requirement
/// feature. Screens call these methods; nothing else touches
/// `SupabaseClient` for requirements.
class RequirementRepository {
  RequirementRepository(this._client);

  final SupabaseClient _client;

  Future<List<Requirement>> fetchBoardRequirements() async {
    final rows = await _client
        .from('requirement')
        .select()
        .eq('status', 'open')
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Requirement.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<Requirement>> fetchOwnRequirements(String negotiatorId) async {
    final rows = await _client
        .from('requirement')
        .select()
        .eq('negotiator_id', negotiatorId)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Requirement.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<Requirement> fetchRequirementById(String requirementId) async {
    final row = await _client.from('requirement').select().eq('requirement_id', requirementId).single();
    return Requirement.fromJson(row);
  }

  /// Reuses the get_negotiator_public_info security-definer RPC
  /// (0004_listing_hardening.sql, renamed in 0015) rather than a new
  /// requirement-specific one -- it already takes any negotiator id and
  /// returns only full_name/ren_number, nothing listing-specific about its
  /// logic.
  Future<ListingOwner> fetchRequirementOwner(String negotiatorId) async {
    final rows = await _client.rpc(
      'get_negotiator_public_info',
      params: {'p_negotiator_id': negotiatorId},
    ) as List;
    if (rows.isEmpty) {
      throw StateError('Negotiator not found: $negotiatorId');
    }
    return ListingOwner.fromJson(rows.first as Map<String, dynamic>);
  }

  /// The `requirement-photos` bucket is private, so photos can only be
  /// rendered through a short-lived signed URL (1 hour).
  Future<String> createSignedUrl(String path) {
    return _client.storage.from('requirement-photos').createSignedUrl(path, 3600);
  }

  Future<String> uploadRequirementPhoto({
    required String negotiatorId,
    required String requirementId,
    required int index,
    required Uint8List bytes,
  }) async {
    final path = '$negotiatorId/$requirementId/$index.jpg';
    await _client.storage.from('requirement-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// Creates the requirement row WITHOUT photos (photo_urls defaults to
  /// '{}'). Photos are uploaded after this returns, using the new
  /// requirement_id in their Storage path, then attached via
  /// updateRequirementPhotos.
  Future<Requirement> createRequirement({
    required String negotiatorId,
    required String propertyType,
    required String transactionType,
    required String state,
    required String area,
    required double budgetMin,
    required double budgetMax,
    int? bedrooms,
    int? bathroomsMin,
    int? builtUpSqftMin,
    double? desiredCommissionSplitPercent,
    bool loanReady = false,
    bool urgentViewingRequired = false,
    String? tenurePreference,
    int? parkingBaysMin,
    int? floorLevelMin,
    String? furnishingPreference,
  }) async {
    final row = await _client
        .from('requirement')
        .insert({
          'negotiator_id': negotiatorId,
          'property_type': propertyType,
          'transaction_type': transactionType,
          'state': state,
          'area': area,
          'budget_min': budgetMin,
          'budget_max': budgetMax,
          'bedrooms': bedrooms,
          'bathrooms_min': bathroomsMin,
          'built_up_sqft_min': builtUpSqftMin,
          'desired_commission_split_percent': desiredCommissionSplitPercent,
          'loan_ready': loanReady,
          'urgent_viewing_required': urgentViewingRequired,
          'tenure_preference': tenurePreference,
          'parking_bays_min': parkingBaysMin,
          'floor_level_min': floorLevelMin,
          'furnishing_preference': furnishingPreference,
        })
        .select()
        .single();
    return Requirement.fromJson(row);
  }

  Future<void> updateRequirementPhotos({required String requirementId, required List<String> photoUrls}) {
    return _client.from('requirement').update({'photo_urls': photoUrls}).eq('requirement_id', requirementId);
  }

  Future<void> updateRequirementStatus({required String requirementId, required String status}) {
    return _client.from('requirement').update({'status': status}).eq('requirement_id', requirementId);
  }

  /// Requires migration 0029_requirement_delete_policy.sql (adds the RLS
  /// DELETE policy -- table-level DELETE grant already exists by default,
  /// same gap class as listing's own delete, fixed the same way in
  /// 0022_listing_delete_policy.sql). `match` cascades on delete from
  /// requirement, and cobroke_request/message/agreement/rating all cascade
  /// from match, so this cleanly removes every match/request/chat/
  /// agreement/rating tied to this requirement at the database level. The
  /// caller (UI) is responsible for blocking this when an ACCEPTED
  /// co-broke request exists, same convention as ListingRepository.deleteListing.
  Future<void> deleteRequirement(String requirementId) {
    return _client.from('requirement').delete().eq('requirement_id', requirementId);
  }

  Future<int> countActiveRequirements(String negotiatorId) async {
    final response = await _client
        .from('requirement')
        .select('requirement_id')
        .eq('negotiator_id', negotiatorId)
        .eq('status', 'open')
        .count(CountOption.exact);
    return response.count;
  }

  /// Global count of ALL open requirements regardless of owner -- powers
  /// the Buyer Match mode's "N Buyer Demands Active" ticker. NOT the same
  /// as countActiveRequirements(negotiatorId) above, which is scoped to
  /// one negotiator's own requirements for the free-tier cap check.
  Future<int> countOpenRequirements() async {
    final response = await _client.from('requirement').select('requirement_id').eq('status', 'open').count(CountOption.exact);
    return response.count;
  }
}

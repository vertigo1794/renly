import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/agreement.dart';

/// The only file in this app that talks to Supabase for the agreement
/// feature. Unlike CobrokeRequestRepository/MessageRepository, this one
/// composes nothing else -- an agreement row carries only split
/// percentages and terms, and needs no owner-name lookup (the
/// counterparty's name is already shown by the surrounding
/// CobrokeRequestCandidate row it's nested inside).
class AgreementRepository {
  AgreementRepository(this._client);

  final SupabaseClient _client;

  Future<void> createAgreement({
    required String requestId,
    required String initiatorId,
    required double splitInitiator,
    required double splitCounterparty,
    String? terms,
  }) async {
    await _client.from('agreement').insert({
      'request_id': requestId,
      'initiator_id': initiatorId,
      'split_initiator': splitInitiator,
      'split_counterparty': splitCounterparty,
      'terms': terms,
    });
  }

  Future<void> acceptAgreement(String agreementId) async {
    final rows = await _client
        .from('agreement')
        .update({'status': 'accepted'})
        .eq('agreement_id', agreementId)
        .select();
    if (rows.isEmpty) {
      throw StateError('Agreement update was rejected (not found or not permitted)');
    }
  }

  Future<void> declineAgreement(String agreementId) async {
    final rows = await _client
        .from('agreement')
        .update({'status': 'declined'})
        .eq('agreement_id', agreementId)
        .select();
    if (rows.isEmpty) {
      throw StateError('Agreement update was rejected (not found or not permitted)');
    }
  }

  /// The most recent agreement for a request, if any -- including a
  /// declined one if no newer proposal has been made yet, so the UI can
  /// tell "never proposed" apart from "was declined."
  Future<Agreement?> fetchAgreementForRequest(String requestId) async {
    final row = await _client
        .from('agreement')
        .select()
        .eq('request_id', requestId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return Agreement.fromJson(row);
  }
}

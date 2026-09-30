import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
import 'models/agreement.dart';

/// The only file in this app that talks to Supabase for the agreement
/// feature. Unlike CobrokeRequestRepository/MessageRepository, this one
/// composes nothing else -- an agreement row carries only split
/// percentages and terms, and needs no owner-name lookup (the
/// counterparty's name is already shown by the surrounding
/// CobrokeRequestCandidate row it's nested inside). It does, since this
/// migration, compose PushNotificationRepository -- same best-effort
/// push pattern as MatchingRepository._notifyMatch /
/// CobrokeRequestRepository._notifyNewRequest.
class AgreementRepository {
  AgreementRepository(this._client, this._pushNotificationRepository);

  final SupabaseClient _client;
  final PushNotificationRepository _pushNotificationRepository;

  /// Proposes a new agreement. Pass [supersedeAgreementId] (an existing
  /// PENDING agreement's id) when this proposal is a counter-offer that
  /// replaces one already on the table -- agreement_one_open_per_request
  /// (0009_agreement.sql) allows at most one open (pending/accepted) row
  /// per request, so the old pending row is marked 'declined' first to
  /// free the slot before inserting the new one. No decline push fires
  /// for that step (it's an implementation detail of superseding, not a
  /// real decline) -- only the new proposal's push fires.
  Future<void> createAgreement({
    required String requestId,
    required String initiatorId,
    required double splitInitiator,
    required double splitCounterparty,
    String? terms,
    String? supersedeAgreementId,
  }) async {
    if (supersedeAgreementId != null) {
      await _setStatus(supersedeAgreementId, 'declined');
    }
    await _client.from('agreement').insert({
      'request_id': requestId,
      'initiator_id': initiatorId,
      'split_initiator': splitInitiator,
      'split_counterparty': splitCounterparty,
      'terms': terms,
    });
    unawaited(_notifyAgreementProposed(requestId: requestId, initiatorId: initiatorId));
  }

  Future<void> acceptAgreement(String agreementId) async {
    final row = await _setStatus(agreementId, 'accepted');
    unawaited(_notifyAgreementResponse(proposerId: row['initiator_id'] as String, accepted: true));
  }

  Future<void> declineAgreement(String agreementId) async {
    final row = await _setStatus(agreementId, 'declined');
    unawaited(_notifyAgreementResponse(proposerId: row['initiator_id'] as String, accepted: false));
  }

  Future<Map<String, dynamic>> _setStatus(String agreementId, String status) async {
    final rows = await _client
        .from('agreement')
        .update({'status': status})
        .eq('agreement_id', agreementId)
        .select();
    if (rows.isEmpty) {
      throw StateError('Agreement update was rejected (not found or not permitted)');
    }
    return rows.first;
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

  Future<void> _notifyAgreementProposed({required String requestId, required String initiatorId}) async {
    try {
      final requestRow =
          await _client.from('cobroke_request').select('match_id').eq('request_id', requestId).single();
      final recipientId = await _client.rpc(
        'get_other_party_in_match',
        params: {'p_match_id': requestRow['match_id'] as String, 'p_actor_id': initiatorId},
      ) as String?;
      if (recipientId == null) return;
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: recipientId,
        category: 'agreement',
        title: 'push_agreement_proposed_title'.tr(),
        body: 'push_agreement_proposed_body'.tr(),
        deepLinkData: const {},
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the agreement that was already stored.
    }
  }

  Future<void> _notifyAgreementResponse({required String proposerId, required bool accepted}) async {
    try {
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: proposerId,
        category: 'agreement',
        title: (accepted ? 'push_agreement_accepted_title' : 'push_agreement_declined_title').tr(),
        body: (accepted ? 'push_agreement_accepted_body' : 'push_agreement_declined_body').tr(),
        deepLinkData: const {},
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the accept/decline that was already stored.
    }
  }
}

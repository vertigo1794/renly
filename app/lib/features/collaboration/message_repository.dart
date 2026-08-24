// app/lib/features/collaboration/message_repository.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
import '../notifications/recipient_resolver.dart';
import 'models/message.dart';

/// The only file in this app that talks to Supabase for the message
/// feature. Composes ListingRepository for sender-name lookups (the
/// get_negotiator_public_info RPC is generic by negotiator id, not
/// listing-specific), same reuse precedent as CobrokeRequestRepository.
class MessageRepository {
  MessageRepository(this._client, this._listingRepository, this._pushNotificationRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;
  final PushNotificationRepository _pushNotificationRepository;

  Future<void> sendMessage({
    required String requestId,
    required String senderId,
    required String body,
  }) async {
    await _client.from('message').insert({
      'request_id': requestId,
      'sender_id': senderId,
      'body': body,
    });
    await _notifyNewMessage(requestId: requestId, senderId: senderId);
  }

  Future<void> _notifyNewMessage({required String requestId, required String senderId}) async {
    try {
      final requestRow = await _client
          .from('cobroke_request')
          .select('match!inner(listing!inner(negotiator_id), requirement!inner(negotiator_id))')
          .eq('request_id', requestId)
          .single();
      final match = requestRow['match'] as Map<String, dynamic>;
      final listingNegotiatorId = (match['listing'] as Map<String, dynamic>)['negotiator_id'] as String;
      final requirementNegotiatorId = (match['requirement'] as Map<String, dynamic>)['negotiator_id'] as String;
      final recipientId = resolveOtherPartyInMatch(
        actorId: senderId,
        listingNegotiatorId: listingNegotiatorId,
        requirementNegotiatorId: requirementNegotiatorId,
      );
      if (recipientId == null) return;
      await _pushNotificationRepository.sendPushNotification(PushPayload(
        recipientNegotiatorId: recipientId,
        category: 'message',
        title: 'push_message_title'.tr(),
        body: 'push_message_body'.tr(),
        deepLinkData: {'request_id': requestId},
      ));
    } catch (_) {
      // Push delivery is best-effort -- a failure here must never undo or
      // surface as an error for the message that was already sent.
    }
  }

  /// Live-updating stream of every message for this request, respecting
  /// RLS server-side (only accepted-request parties ever receive rows).
  /// Each emission carries the FULL current row set for the filter, not a
  /// delta -- so this single stream covers both the initial history load
  /// and every subsequent live insert, with no separate merge logic.
  Stream<List<Message>> messagesStream(String requestId) {
    // Sort the PARSED DateTime in Dart, not via .order('sent_at') on the
    // stream builder. SupabaseStreamBuilder merges rows from two different
    // sources -- the initial PostgREST fetch and live Realtime INSERT
    // payloads -- and sorts the raw sent_at STRING. Those two sources
    // format timestamptz differently ("2026-08-24T10:00:00+00:00" from
    // PostgREST vs "2026-08-24 10:00:00+00" from a Realtime payload,
    // space- not T-separated), so a raw string comparison sorts every
    // live-delivered message ABOVE the entire same-day history instead of
    // below it. Sorting the parsed DateTime sidesteps the format mismatch
    // entirely (and makes ascending: true unnecessary -- no .order() call
    // at all).
    return _client
        .from('message')
        .stream(primaryKey: ['message_id'])
        .eq('request_id', requestId)
        .map((rows) {
          final messages = rows.map(Message.fromJson).toList();
          messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
          return messages;
        });
  }

  Future<ListingOwner> fetchSenderName(String negotiatorId) {
    return _listingRepository.fetchListingOwner(negotiatorId);
  }
}

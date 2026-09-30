// app/lib/features/collaboration/message_repository.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import '../notifications/models/push_payload.dart';
import '../notifications/push_notification_repository.dart';
import 'models/conversation_summary.dart';
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
    String? body,
    String? attachmentUrl,
  }) async {
    await _client.from('message').insert({
      'request_id': requestId,
      'sender_id': senderId,
      'body': body,
      'attachment_url': attachmentUrl,
    });
    unawaited(_notifyNewMessage(requestId: requestId, senderId: senderId));
  }

  /// The `chat-attachments` bucket is private (same reasoning as
  /// `listing-photos`), so an attachment can only be rendered through a
  /// short-lived signed URL.
  Future<String> createAttachmentSignedUrl(String path) {
    return _client.storage.from('chat-attachments').createSignedUrl(path, 3600);
  }

  /// Path convention `{request_id}/{timestamp}.jpg`, mirroring
  /// ListingRepository.uploadListingPhoto's `{negotiator_id}/{listing_id}/{n}.jpg`.
  /// request_id (not negotiator_id) is the folder segment here since the
  /// storage RLS policy scopes access by the conversation, not the uploader.
  Future<String> uploadChatAttachment({required String requestId, required Uint8List bytes}) async {
    final path = '$requestId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('chat-attachments').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  Future<void> _notifyNewMessage({required String requestId, required String senderId}) async {
    try {
      final requestRow = await _client
          .from('cobroke_request')
          .select('match_id')
          .eq('request_id', requestId)
          .single();
      final matchId = requestRow['match_id'] as String;
      final recipientId = await _client.rpc(
        'get_other_party_in_match',
        params: {'p_match_id': matchId, 'p_actor_id': senderId},
      ) as String?;
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

  /// Whether the current negotiator has ANY unread message across ALL of
  /// their conversations -- backs the bottom-nav Chat tab's presence dot
  /// (no number, just on/off). No request_id filter needed: message_select's
  /// own RLS (0008_messaging.sql) already restricts visible rows to
  /// accepted conversations this negotiator is a party to, same reasoning
  /// as MatchingRepository.fetchMyMatches(). limit(1) since only presence,
  /// not a count, is needed.
  Future<bool> hasUnreadMessages(String negotiatorId) async {
    final rows = await _client
        .from('message')
        .select('message_id')
        .neq('sender_id', negotiatorId)
        .isFilter('read_at', null)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Marks every unread message in this conversation that the CURRENT user
  /// did not send as read. Relies on message_update_read_at's own RLS check
  /// (accepted-request party, not the sender) rather than re-deriving that
  /// check client-side -- an update to a row this policy rejects silently
  /// updates zero rows rather than throwing, which is the correct outcome
  /// here (e.g. calling this before the request is actually accepted yet
  /// should be a harmless no-op, not an error).
  Future<void> markConversationRead(String requestId, String currentNegotiatorId) async {
    await _client
        .from('message')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('request_id', requestId)
        .neq('sender_id', currentNegotiatorId)
        .isFilter('read_at', null);
  }

  /// The latest message for this conversation (via the conversation_last_message
  /// view) plus how many of the OTHER party's messages are still unread by
  /// the current user. Returns null if the conversation has no messages yet
  /// (a freshly-accepted request can have zero messages) -- callers must
  /// handle that as "no preview yet", not an error.
  Future<ConversationSummary?> fetchConversationSummary(String requestId, String currentNegotiatorId) async {
    final lastMessageRow = await _client
        .from('conversation_last_message')
        .select()
        .eq('request_id', requestId)
        .maybeSingle();
    if (lastMessageRow == null) return null;

    final unreadCount = await _client
        .from('message')
        .select('message_id')
        .eq('request_id', requestId)
        .neq('sender_id', currentNegotiatorId)
        .isFilter('read_at', null)
        .count(CountOption.exact);

    return ConversationSummary(
      requestId: lastMessageRow['request_id'] as String,
      senderId: lastMessageRow['sender_id'] as String,
      // An image-only message has no body -- fall back to a photo preview
      // label so the conversation list never renders a blank last-message.
      body: (lastMessageRow['body'] as String?) ?? 'message_photo_preview'.tr(),
      sentAt: DateTime.parse(lastMessageRow['sent_at'] as String),
      unreadCount: unreadCount.count,
      readAt: lastMessageRow['read_at'] == null ? null : DateTime.parse(lastMessageRow['read_at'] as String),
    );
  }
}

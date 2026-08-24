// app/lib/features/collaboration/message_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import 'models/message.dart';

/// The only file in this app that talks to Supabase for the message
/// feature. Composes ListingRepository for sender-name lookups (the
/// get_negotiator_public_info RPC is generic by negotiator id, not
/// listing-specific), same reuse precedent as CobrokeRequestRepository.
class MessageRepository {
  MessageRepository(this._client, this._listingRepository);

  final SupabaseClient _client;
  final ListingRepository _listingRepository;

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

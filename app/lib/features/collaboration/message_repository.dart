// app/lib/features/collaboration/message_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../listing/listing_repository.dart';
import '../listing/models/listing_owner.dart';
import 'models/message.dart';

/// The only file in this app that talks to Supabase for the message
/// feature. Composes ListingRepository for sender-name lookups (the
/// get_listing_owner_info RPC is generic by negotiator id, not
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
    // SupabaseStreamBuilder.order() defaults to ascending: false (unlike
    // the plain Postgrest query builder, which defaults to true) --
    // explicit ascending: true is required here for oldest-first
    // chronological chat order, or every message list renders reversed.
    return _client
        .from('message')
        .stream(primaryKey: ['message_id'])
        .eq('request_id', requestId)
        .order('sent_at', ascending: true)
        .map((rows) => rows.map(Message.fromJson).toList());
  }

  Future<ListingOwner> fetchSenderName(String negotiatorId) {
    return _listingRepository.fetchListingOwner(negotiatorId);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/subscription_status.dart';

/// The only file in this app that talks to Supabase for the subscription
/// feature. `createSubscription`/`createPortalSession` call Edge
/// Functions (the only privileged-write path for the 4 new columns on
/// `negotiator` -- no direct client UPDATE exists for any of them, unlike
/// every other repository in this codebase). `subscriptionStream` is a
/// plain read, same shape as MessageRepository's Realtime precedent.
class SubscriptionRepository {
  SubscriptionRepository(this._client);

  final SupabaseClient _client;

  Future<String> createSubscription() async {
    final response = await _client.functions.invoke('create-subscription');
    final clientSecret = (response.data as Map<String, dynamic>?)?['client_secret'] as String?;
    if (clientSecret == null) {
      throw StateError('create-subscription did not return a client_secret.');
    }
    return clientSecret;
  }

  Future<String> createPortalSession() async {
    final response = await _client.functions.invoke('create-portal-session');
    final url = (response.data as Map<String, dynamic>?)?['url'] as String?;
    if (url == null) {
      throw StateError('create-portal-session did not return a url.');
    }
    return url;
  }

  /// Live-updating subscription state for one negotiator -- a single row
  /// filter, so there's no cross-source sort-order concern the way
  /// MessageRepository.messagesStream has to guard against (that lesson
  /// only applies when merging an ordered multi-row history with live
  /// inserts; this is always exactly one row).
  Stream<SubscriptionStatus> subscriptionStream(String negotiatorId) {
    return _client
        .from('negotiator')
        .stream(primaryKey: ['negotiator_id'])
        .eq('negotiator_id', negotiatorId)
        .map((rows) {
          // A bare `rows.first` throws `StateError: No element` here,
          // which says nothing about what actually went wrong. An empty
          // snapshot means the negotiator row is genuinely missing (or
          // unreadable), so name that in the message -- otherwise the
          // error surfaces on the Subscription screen as a generic
          // failure with no way to tell it apart from a network problem.
          if (rows.isEmpty) {
            throw StateError('No negotiator row found for id $negotiatorId');
          }
          return SubscriptionStatus.fromJson(rows.first);
        });
  }
}

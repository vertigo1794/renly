/// Body sent to the send-push-notification Edge Function. category is one
/// of 'match' | 'message' | 'cobroke_request' | 'agreement' -- kept as a plain String
/// (not an enum) since it round-trips through JSON to Deno either way and
/// an enum would just add a mapping step with no real type safety gained.
class PushPayload {
  const PushPayload({
    required this.recipientNegotiatorId,
    required this.category,
    required this.title,
    required this.body,
    required this.deepLinkData,
  });

  final String recipientNegotiatorId;
  final String category;
  final String title;
  final String body;
  final Map<String, String> deepLinkData;

  Map<String, dynamic> toJson() => {
        'recipient_negotiator_id': recipientNegotiatorId,
        'category': category,
        'title': title,
        'body': body,
        'deep_link_data': deepLinkData,
      };
}

/// One row from the `conversation_last_message` view (the latest message in
/// a single request's conversation) plus a separately-queried unread count.
/// Not a `Message` -- `conversation_last_message`'s DISTINCT ON collapses
/// to one row per request_id with no stable `message_id` of its own (a new
/// incoming message replaces which row wins the DISTINCT ON, so any id
/// here would misleadingly suggest a stable identity that doesn't exist).
class ConversationSummary {
  final String requestId;
  final String senderId;
  final String body;
  final DateTime sentAt;
  final int unreadCount;
  final DateTime? readAt;

  const ConversationSummary({
    required this.requestId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    required this.unreadCount,
    this.readAt,
  });
}

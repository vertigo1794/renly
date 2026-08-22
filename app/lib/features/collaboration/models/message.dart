/// A row from the `message` table.
class Message {
  final String messageId;
  final String requestId;
  final String senderId;
  final String body;
  final DateTime sentAt;

  const Message({
    required this.messageId,
    required this.requestId,
    required this.senderId,
    required this.body,
    required this.sentAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      messageId: json['message_id'] as String,
      requestId: json['request_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
    );
  }
}

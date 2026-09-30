/// A row from the `message` table.
class Message {
  final String messageId;
  final String requestId;
  final String senderId;
  final String? body;
  final String? attachmentUrl;
  final DateTime sentAt;
  final DateTime? readAt;

  const Message({
    required this.messageId,
    required this.requestId,
    required this.senderId,
    this.body,
    this.attachmentUrl,
    required this.sentAt,
    this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      messageId: json['message_id'] as String,
      requestId: json['request_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String?,
      attachmentUrl: json['attachment_url'] as String?,
      sentAt: DateTime.parse(json['sent_at'] as String),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
    );
  }
}

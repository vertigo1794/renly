/// A row from the `notification` table.
class AppNotification {
  final String notificationId;
  final String category;
  final String title;
  final String body;
  final Map<String, String> deepLinkData;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.notificationId,
    required this.category,
    required this.title,
    required this.body,
    required this.deepLinkData,
    required this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawDeepLinkData = json['deep_link_data'] as Map<String, dynamic>? ?? const {};
    return AppNotification(
      notificationId: json['notification_id'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      deepLinkData: rawDeepLinkData.map((key, value) => MapEntry(key, value.toString())),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A row from the `cobroke_request` table.
class CobrokeRequest {
  final String requestId;
  final String matchId;
  final String initiatorId;
  final String status;
  final DateTime createdAt;

  const CobrokeRequest({
    required this.requestId,
    required this.matchId,
    required this.initiatorId,
    required this.status,
    required this.createdAt,
  });

  factory CobrokeRequest.fromJson(Map<String, dynamic> json) {
    return CobrokeRequest(
      requestId: json['request_id'] as String,
      matchId: json['match_id'] as String,
      initiatorId: json['initiator_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

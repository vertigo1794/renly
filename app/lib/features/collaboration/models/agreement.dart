/// A row from the `agreement` table.
class Agreement {
  final String agreementId;
  final String requestId;
  final String initiatorId;
  final double splitInitiator;
  final double splitCounterparty;
  final String? terms;
  final String status;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  const Agreement({
    required this.agreementId,
    required this.requestId,
    required this.initiatorId,
    required this.splitInitiator,
    required this.splitCounterparty,
    this.terms,
    required this.status,
    this.acceptedAt,
    required this.createdAt,
  });

  factory Agreement.fromJson(Map<String, dynamic> json) {
    return Agreement(
      agreementId: json['agreement_id'] as String,
      requestId: json['request_id'] as String,
      initiatorId: json['initiator_id'] as String,
      splitInitiator: (json['split_initiator'] as num).toDouble(),
      splitCounterparty: (json['split_counterparty'] as num).toDouble(),
      terms: json['terms'] as String?,
      status: json['status'] as String,
      acceptedAt: json['accepted_at'] == null ? null : DateTime.parse(json['accepted_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

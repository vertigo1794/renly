/// A row from the `negotiator` table, scoped to fields this app's auth
/// flow needs (not every ERD column).
class Negotiator {
  final String negotiatorId;
  final String fullName;
  final String verificationStatus;

  const Negotiator({
    required this.negotiatorId,
    required this.fullName,
    required this.verificationStatus,
  });

  factory Negotiator.fromJson(Map<String, dynamic> json) {
    return Negotiator(
      negotiatorId: json['negotiator_id'] as String,
      fullName: json['full_name'] as String,
      verificationStatus: json['verification_status'] as String,
    );
  }
}

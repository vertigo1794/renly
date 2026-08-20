/// A row from the `requirement` table.
class Requirement {
  final String requirementId;
  final String negotiatorId;
  final String propertyType;
  final String transactionType;
  final String state;
  final String area;
  final double budgetMin;
  final double budgetMax;
  final int? bedrooms;
  final List<String> photoUrls;
  final String status;

  const Requirement({
    required this.requirementId,
    required this.negotiatorId,
    required this.propertyType,
    required this.transactionType,
    required this.state,
    required this.area,
    required this.budgetMin,
    required this.budgetMax,
    this.bedrooms,
    required this.photoUrls,
    required this.status,
  });

  factory Requirement.fromJson(Map<String, dynamic> json) {
    return Requirement(
      requirementId: json['requirement_id'] as String,
      negotiatorId: json['negotiator_id'] as String,
      propertyType: json['property_type'] as String,
      transactionType: json['transaction_type'] as String,
      state: json['state'] as String,
      area: json['area'] as String,
      budgetMin: (json['budget_min'] as num).toDouble(),
      budgetMax: (json['budget_max'] as num).toDouble(),
      bedrooms: json['bedrooms'] as int?,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      status: json['status'] as String,
    );
  }
}

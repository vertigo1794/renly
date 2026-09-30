/// A row from the `rating` table.
class Rating {
  final String ratingId;
  final String agreementId;
  final String? raterId;
  final String ratedId;
  final int stars;
  final String? reviewText;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Rating({
    required this.ratingId,
    required this.agreementId,
    required this.raterId,
    required this.ratedId,
    required this.stars,
    this.reviewText,
    required this.createdAt,
    this.updatedAt,
  });

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      ratingId: json['rating_id'] as String,
      agreementId: json['agreement_id'] as String,
      raterId: json['rater_id'] as String?,
      ratedId: json['rated_id'] as String,
      stars: json['stars'] as int,
      reviewText: json['review_text'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null ? null : DateTime.parse(json['updated_at'] as String),
    );
  }
}

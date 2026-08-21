// app/lib/features/matching/models/match.dart

/// A row from the `match` table.
class Match {
  final String matchId;
  final String listingId;
  final String requirementId;
  final int score;
  final DateTime createdAt;

  const Match({
    required this.matchId,
    required this.listingId,
    required this.requirementId,
    required this.score,
    required this.createdAt,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      matchId: json['match_id'] as String,
      listingId: json['listing_id'] as String,
      requirementId: json['requirement_id'] as String,
      score: json['score'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

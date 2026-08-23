// app/test/features/ratings/models/rating_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/ratings/models/rating.dart';

void main() {
  group('Rating.fromJson', () {
    test('parses a fresh rating with no review text or update', () {
      final rating = Rating.fromJson({
        'rating_id': 'rat-1',
        'agreement_id': 'agr-1',
        'rater_id': 'n-1',
        'rated_id': 'n-2',
        'stars': 5,
        'review_text': null,
        'created_at': '2026-08-24T10:00:00.000Z',
        'updated_at': null,
      });

      expect(rating.ratingId, 'rat-1');
      expect(rating.agreementId, 'agr-1');
      expect(rating.raterId, 'n-1');
      expect(rating.ratedId, 'n-2');
      expect(rating.stars, 5);
      expect(rating.reviewText, isNull);
      expect(rating.createdAt, DateTime.parse('2026-08-24T10:00:00.000Z'));
      expect(rating.updatedAt, isNull);
    });

    test('parses an edited rating with review text and updated_at', () {
      final rating = Rating.fromJson({
        'rating_id': 'rat-2',
        'agreement_id': 'agr-2',
        'rater_id': 'n-3',
        'rated_id': 'n-4',
        'stars': 3,
        'review_text': 'Good to work with, minor communication delays.',
        'created_at': '2026-08-24T10:00:00.000Z',
        'updated_at': '2026-08-24T11:30:00.000Z',
      });

      expect(rating.stars, 3);
      expect(rating.reviewText, 'Good to work with, minor communication delays.');
      expect(rating.updatedAt, DateTime.parse('2026-08-24T11:30:00.000Z'));
    });
  });
}

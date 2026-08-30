import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/brutalist_card.dart';
import 'models/rating_candidate.dart';
import 'rating_providers.dart';

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('rating_reviews_title'.tr())),
      body: negotiatorId == null ? const SizedBox.shrink() : _ReviewsList(negotiatorId: negotiatorId),
    );
  }
}

class _ReviewsList extends ConsumerWidget {
  const _ReviewsList({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsForNegotiatorProvider(negotiatorId));

    return ratingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
      data: (candidates) {
        if (candidates.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/illustrations/reviews_empty.png',
                  height: 160,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                Text('rating_reviews_empty'.tr()),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: candidates.length,
          itemBuilder: (context, index) => _ReviewRow(candidate: candidates[index]),
        );
      },
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.candidate});

  final RatingCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final rating = candidate.rating;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: BrutalistCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.rater.fullName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${rating.stars} / 5'),
            if (rating.reviewText != null && rating.reviewText!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(rating.reviewText!),
            ],
            const SizedBox(height: 4),
            Text('${rating.createdAt.day}/${rating.createdAt.month}/${rating.createdAt.year}'),
          ],
        ),
      ),
    );
  }
}

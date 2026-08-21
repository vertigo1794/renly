import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../listing/listing_formatting.dart';
import 'matching_providers.dart';

/// Ranked listing matches for one requirement. Reached via "View Matches"
/// on RequirementDetailScreen.
class MatchesForRequirementScreen extends ConsumerWidget {
  const MatchesForRequirementScreen({super.key, required this.requirementId});

  final String requirementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesForRequirementProvider(requirementId));

    return Scaffold(
      appBar: AppBar(title: Text('matching_matches_title'.tr())),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (matches) {
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final candidate = matches[index];
              final listing = candidate.listing;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => context.push('/property/${listing.listingId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(ListingFormatting.formatPrice(listing.price, listing.transactionType)),
                        const SizedBox(height: 4),
                        Text(listing.area, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

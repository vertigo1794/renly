import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../collaboration/send_cobroke_request_action.dart';
import '../listing/listing_formatting.dart';
import '../requirement/requirement_formatting.dart';
import 'matching_providers.dart';

/// All matches touching the negotiator's own listings or requirements,
/// either side. Reached via "My Matches" on HomePlaceholderScreen.
class MyMatchesScreen extends ConsumerWidget {
  const MyMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(myMatchesProvider);
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('matching_my_matches_title'.tr())),
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
              final isMyListing = candidate.listing.negotiatorId == currentNegotiatorId;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => isMyListing
                      ? context.push('/requirement-board/${candidate.requirement.requirementId}')
                      : context.push('/property/${candidate.listing.listingId}'),
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
                        if (isMyListing) ...[
                          Text(
                            RequirementFormatting.formatBudgetRange(
                              candidate.requirement.budgetMin,
                              candidate.requirement.budgetMax,
                              candidate.requirement.transactionType,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(candidate.requirement.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ] else ...[
                          Text(ListingFormatting.formatPrice(candidate.listing.price, candidate.listing.transactionType)),
                          const SizedBox(height: 4),
                          Text(candidate.listing.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
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

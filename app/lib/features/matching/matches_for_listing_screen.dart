import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../collaboration/send_cobroke_request_action.dart';
import '../requirement/requirement_formatting.dart';
import 'matching_providers.dart';

/// Ranked requirement matches for one listing. Reached via "View Matches"
/// on PropertyDetailScreen.
class MatchesForListingScreen extends ConsumerWidget {
  const MatchesForListingScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesForListingProvider(listingId));

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
              final requirement = candidate.requirement;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
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
                        Text(
                          RequirementFormatting.formatBudgetRange(
                            requirement.budgetMin,
                            requirement.budgetMax,
                            requirement.transactionType,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(requirement.area, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/illustrations/matching_empty.png',
                    height: 160,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  Text('matching_empty'.tr()),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final candidate = matches[index];
              final requirement = candidate.requirement;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                    child: BrutalistCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${candidate.score}/100',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
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
                          BrutalistButton(
                            label: 'cobroke_request_send'.tr(),
                            onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                            icon: PhosphorIcons.handshake(PhosphorIconsStyle.bold),
                          ),
                        ],
                      ),
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
